"""Google Gemini provider implementation."""

import asyncio

from namingpaper.config import get_settings
from namingpaper.models import PDFContent, PaperMetadata
from namingpaper.providers.base import AIProvider, EXTRACTION_PROMPT

try:
    from google import genai
    from google.genai import types

    GEMINI_AVAILABLE = True
except ImportError:
    GEMINI_AVAILABLE = False
    genai = None
    types = None


class GeminiProvider(AIProvider):
    """Google Gemini provider."""

    DEFAULT_MODEL = "gemini-2.0-flash"

    def __init__(self, api_key: str, model: str | None = None):
        if not GEMINI_AVAILABLE:
            raise ImportError(
                "Gemini package not installed. Run: pip install namingpaper[gemini]"
            )
        self.client = genai.Client(api_key=api_key)
        self.model_name = model or self.DEFAULT_MODEL

    async def extract_metadata(self, content: PDFContent) -> PaperMetadata:
        """Extract metadata using Gemini."""
        settings = get_settings()
        text = self._truncate_text(content.text, settings.max_text_chars)

        # Build prompt parts
        parts = []

        # Add image if available
        if self._should_include_image(content):
            parts.append(
                types.Part.from_bytes(
                    data=content.first_page_image,
                    mime_type="image/png",
                )
            )

        # Add text and prompt
        parts.append(f"Paper text:\n\n{text}\n\n{EXTRACTION_PROMPT}")

        # Call Gemini API in thread to avoid blocking event loop
        try:
            response = await asyncio.to_thread(
                self.client.models.generate_content,
                model=self.model_name,
                contents=parts,
            )
        except Exception as e:
            err = str(e).lower()
            if "not found" in err or "404" in err or "does not exist" in err:
                raise RuntimeError(
                    f"Model not found. Check available models at https://ai.google.dev/gemini-api/docs/models"
                ) from e
            if "api key" in err or "permission" in err:
                raise RuntimeError(
                    "Invalid Gemini API key. Check your NAMINGPAPER_GEMINI_API_KEY."
                ) from e
            raise

        # Parse response
        response_text = response.text
        if not response_text:
            raise RuntimeError("Gemini returned an empty response.")

        return self._parse_response_json(response_text, "Gemini")

    async def call_raw(self, prompt: str) -> str:
        """Send a raw prompt and return response text."""
        try:
            response = await asyncio.to_thread(
                self.client.models.generate_content,
                model=self.model_name,
                contents=prompt,
            )
        except Exception as e:
            err = str(e).lower()
            if "api key" in err or "permission" in err:
                raise RuntimeError(
                    "Invalid Gemini API key. Check your NAMINGPAPER_GEMINI_API_KEY."
                ) from e
            raise
        response_text = response.text
        if not response_text:
            raise RuntimeError("Gemini returned an empty response.")
        return response_text
