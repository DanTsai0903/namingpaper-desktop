"""LM Studio provider implementation for local LLM inference."""

import base64
import logging

import httpx

from namingpaper.config import get_settings
from namingpaper.models import PDFContent, PaperMetadata
from namingpaper.providers.base import AIProvider, EXTRACTION_PROMPT


class LMStudioProvider(AIProvider):
    """LM Studio provider for local LLM inference.

    Uses LM Studio's OpenAI-compatible API at /v1/chat/completions.
    Supports an optional two-stage pipeline: VLM OCR + text model for metadata parsing.
    """

    DEFAULT_TEXT_MODEL = "qwen3.5-2b-optiq"
    DEFAULT_BASE_URL = "http://localhost:1234"

    def __init__(
        self,
        model: str | None = None,
        base_url: str | None = None,
        ocr_model: str | None = None,
        api_key: str | None = None,
    ):
        self.text_model = (model or self.DEFAULT_TEXT_MODEL).strip()
        self.ocr_model = ocr_model.strip() if ocr_model else None
        self.base_url = (base_url or self.DEFAULT_BASE_URL).rstrip("/")
        self.api_key = api_key
        self._client: httpx.AsyncClient | None = None

    def _get_client(self) -> httpx.AsyncClient:
        """Get or create a reusable async HTTP client."""
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(timeout=300.0)
        return self._client

    async def aclose(self) -> None:
        """Close the underlying HTTP client."""
        if self._client is not None and not self._client.is_closed:
            await self._client.aclose()
            self._client = None

    async def __aenter__(self) -> "LMStudioProvider":
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb) -> None:
        await self.aclose()

    async def extract_metadata(self, content: PDFContent) -> PaperMetadata:
        """Extract metadata using LM Studio pipeline.

        If text extraction already produced usable text, skip the OCR stage
        and go straight to metadata parsing. OCR requires lmstudio_ocr_model
        to be configured.
        """
        settings = get_settings()

        if content.text and len(content.text.strip()) > 100:
            combined_text = content.text
        elif self.ocr_model and content.first_page_image:
            try:
                ocr_text = await self._ocr_extract(content.first_page_image)
                combined_text = f"{ocr_text}\n\n{content.text}" if content.text else ocr_text
            except RuntimeError:
                logging.getLogger(__name__).warning(
                    "OCR model unavailable, falling back to text-only extraction"
                )
                combined_text = content.text or ""
        else:
            combined_text = content.text or ""

        text = self._truncate_text(combined_text, settings.max_text_chars)
        return await self._parse_metadata(text)

    async def _ocr_extract(self, image_data: bytes) -> str:
        """Extract text from image using VLM OCR model."""
        image_b64 = base64.standard_b64encode(image_data).decode("utf-8")

        payload = {
            "model": self.ocr_model,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": "Extract all text from this academic paper image. Include title, authors, abstract, and any visible text.",
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/png;base64,{image_b64}",
                            },
                        },
                    ],
                }
            ],
            "max_tokens": 2048,
            "stream": False,
            "ttl": 300,
        }

        result = await self._call_lmstudio(payload)
        return result["choices"][0]["message"]["content"]

    async def _parse_metadata(self, text: str) -> PaperMetadata:
        """Parse metadata from text using text model."""
        prompt = f"Paper text:\n\n{text}\n\n{EXTRACTION_PROMPT}"

        payload = {
            "model": self.text_model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 2048,
            "stream": False,
            "ttl": 300,
        }

        result = await self._call_lmstudio(payload)
        response_text = result["choices"][0]["message"]["content"]

        if not response_text:
            raise RuntimeError(
                f"LM Studio returned empty response. Model '{self.text_model}' may not be loaded."
            )

        return self._parse_response_json(response_text, "LM Studio")

    async def call_raw(self, prompt: str) -> str:
        """Send a raw prompt and return response text."""
        payload = {
            "model": self.text_model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 2048,
            "stream": False,
            "ttl": 300,
        }

        result = await self._call_lmstudio(payload)
        response_text = result["choices"][0]["message"]["content"]

        if not response_text:
            raise RuntimeError("LM Studio returned an empty response.")

        return response_text

    async def _call_lmstudio(self, payload: dict) -> dict:
        """Make a request to LM Studio's OpenAI-compatible API."""
        try:
            client = self._get_client()
            headers = {}
            if self.api_key:
                headers["Authorization"] = f"Bearer {self.api_key}"
            response = await client.post(
                f"{self.base_url}/v1/chat/completions",
                json=payload,
                headers=headers,
            )
            response.raise_for_status()
        except httpx.HTTPStatusError as e:
            model = payload.get("model", "unknown")
            if e.response.status_code == 401:
                raise RuntimeError(
                    f"LM Studio requires an API key.\n\n"
                    f"Set it via environment variable:\n"
                    f"  export NAMINGPAPER_LMSTUDIO_API_KEY=your-key\n\n"
                    f"Or in ~/.namingpaper/config.toml:\n"
                    f"  lmstudio_api_key = \"your-key\""
                ) from e
            if e.response.status_code == 404:
                raise RuntimeError(
                    f"Model '{model}' not found on LM Studio server.\n\n"
                    f"Make sure the model is downloaded and loaded in the LM Studio app.\n"
                    f"Check available models at {self.base_url}/v1/models"
                ) from e
            raise RuntimeError(
                f"LM Studio API error: {e.response.status_code} - {e.response.text}"
            ) from e
        except httpx.ConnectError:
            raise RuntimeError(
                f"Cannot connect to LM Studio at {self.base_url}.\n\n"
                f"LM Studio is a desktop app for running LLMs locally.\n"
                f"  1. Download from https://lmstudio.ai\n"
                f"  2. Load a model and start the local server\n\n"
                f"Or use Ollama instead: namingpaper rename --provider ollama <file>"
            )
        except httpx.ReadTimeout:
            model = payload.get("model", "unknown")
            raise RuntimeError(
                f"LM Studio timed out after 300s. The model '{model}' may still be loading "
                f"or the input may be too large."
            )

        return response.json()
