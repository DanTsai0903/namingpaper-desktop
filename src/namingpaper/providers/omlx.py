"""oMLX provider implementation for Apple Silicon local inference."""

import base64
import logging

import httpx

from namingpaper.config import get_settings
from namingpaper.models import PDFContent, PaperMetadata
from namingpaper.providers.base import AIProvider, EXTRACTION_PROMPT


class oMLXProvider(AIProvider):
    """oMLX provider for local LLM inference on Apple Silicon.

    Uses oMLX's OpenAI-compatible API at /v1/chat/completions.
    Supports a two-stage pipeline: VLM OCR + text model for metadata parsing.
    """

    DEFAULT_TEXT_MODEL = "mlx-community/Qwen3-8B-4bit"
    DEFAULT_OCR_MODEL = "mlx-community/Qwen2.5-VL-7B-Instruct-4bit"
    DEFAULT_BASE_URL = "http://localhost:8000"

    def __init__(
        self,
        model: str | None = None,
        base_url: str | None = None,
        ocr_model: str | None = None,
        api_key: str | None = None,
        reasoning: bool | None = None,
    ):
        self.text_model = model or self.DEFAULT_TEXT_MODEL
        self.ocr_model = ocr_model or self.DEFAULT_OCR_MODEL
        self.base_url = (base_url or self.DEFAULT_BASE_URL).rstrip("/")
        self.api_key = api_key
        self.reasoning = reasoning
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

    async def __aenter__(self) -> "oMLXProvider":
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb) -> None:
        await self.aclose()

    async def extract_metadata(self, content: PDFContent) -> PaperMetadata:
        """Extract metadata using oMLX pipeline.

        If text extraction already produced usable text, skip the slow OCR stage
        and go straight to metadata parsing.
        """
        settings = get_settings()

        if content.text and len(content.text.strip()) > 100:
            combined_text = content.text
        elif content.first_page_image:
            try:
                ocr_text = await self._ocr_extract(content.first_page_image)
                combined_text = f"{ocr_text}\n\n{content.text}" if content.text else ocr_text
            except RuntimeError:
                logging.getLogger(__name__).warning(
                    "OCR model unavailable, falling back to text-only extraction"
                )
                combined_text = content.text or ""
        else:
            combined_text = content.text

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
        }

        result = await self._call_omlx(payload)
        return result["choices"][0]["message"]["content"]

    def _build_payload(self, model: str, messages: list[dict], max_tokens: int = 2048) -> dict:
        """Build a request payload, disabling thinking mode for Qwen3 models."""
        payload: dict = {
            "model": model,
            "messages": messages,
            "max_tokens": max_tokens,
            "stream": False,
        }
        # Qwen3 models emit chain-of-thought by default, wasting tokens.
        # Disable via chat_template_kwargs unless reasoning is explicitly enabled.
        if "qwen3" in model.lower() and not self.reasoning:
            payload["chat_template_kwargs"] = {"enable_thinking": False}
        return payload

    async def _parse_metadata(self, text: str) -> PaperMetadata:
        """Parse metadata from text using text model."""
        prompt = f"Paper text:\n\n{text}\n\n{EXTRACTION_PROMPT}"

        payload = self._build_payload(
            self.text_model,
            [{"role": "user", "content": prompt}],
        )

        result = await self._call_omlx(payload)
        response_text = result["choices"][0]["message"]["content"]

        if not response_text:
            raise RuntimeError(
                f"oMLX returned empty response. Model '{self.text_model}' may not be available."
            )

        return self._parse_response_json(response_text, "oMLX")

    async def call_raw(self, prompt: str) -> str:
        """Send a raw prompt and return response text."""
        payload = self._build_payload(
            self.text_model,
            [{"role": "user", "content": prompt}],
        )

        result = await self._call_omlx(payload)
        response_text = result["choices"][0]["message"]["content"]

        if not response_text:
            raise RuntimeError("oMLX returned an empty response.")

        return response_text

    async def _call_omlx(self, payload: dict) -> dict:
        """Make a request to oMLX's OpenAI-compatible API."""
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
                    f"oMLX requires an API key.\n\n"
                    f"Set it via environment variable:\n"
                    f"  export NAMINGPAPER_OMLX_API_KEY=your-key\n\n"
                    f"Or in ~/.namingpaper/config.toml:\n"
                    f"  omlx_api_key = \"your-key\""
                ) from e
            if e.response.status_code == 404:
                raise RuntimeError(
                    f"Model '{model}' not found on oMLX server.\n\n"
                    f"oMLX uses HuggingFace model IDs (e.g., mlx-community/...).\n"
                    f"Check available models at {self.base_url}/v1/models"
                ) from e
            raise RuntimeError(
                f"oMLX API error: {e.response.status_code} - {e.response.text}"
            ) from e
        except httpx.ConnectError:
            raise RuntimeError(
                f"Cannot connect to oMLX at {self.base_url}.\n\n"
                f"oMLX is an Apple Silicon LLM server. To set up:\n"
                f"  1. Install: brew tap jundot/omlx && brew install omlx\n"
                f"  2. Start: brew services start omlx\n\n"
                f"Or use Ollama instead: namingpaper rename --provider ollama <file>"
            )
        except httpx.ReadTimeout:
            model = payload.get("model", "unknown")
            raise RuntimeError(
                f"oMLX timed out after 300s. The model '{model}' may be downloading or too slow."
            )

        return response.json()
