"""Tests for oMLX provider."""

import json

import httpx
import pytest

from namingpaper.models import PDFContent
from namingpaper.providers.omlx import oMLXProvider


def _chat_response(content: str) -> dict:
    """Build a fake OpenAI-compatible chat completion response."""
    return {
        "choices": [
            {
                "message": {"content": content},
                "finish_reason": "stop",
            }
        ]
    }


class TestoMLXProviderDefaults:
    def test_default_values(self):
        p = oMLXProvider()
        assert p.text_model == "mlx-community/Qwen3.5-2B-MLX-4bit"
        assert p.ocr_model == "mlx-community/DeepSeek-OCR-8bit"
        assert p.base_url == "http://localhost:8000"

    def test_custom_values(self):
        p = oMLXProvider(
            model="mlx-community/Llama-3.2-3B-Instruct-4bit",
            base_url="http://localhost:9000",
            ocr_model="mlx-community/Qwen3.5-VL-4bit",
        )
        assert p.text_model == "mlx-community/Llama-3.2-3B-Instruct-4bit"
        assert p.base_url == "http://localhost:9000"
        assert p.ocr_model == "mlx-community/Qwen3.5-VL-4bit"

    def test_base_url_strips_trailing_slash(self):
        p = oMLXProvider(base_url="http://localhost:8000/")
        assert p.base_url == "http://localhost:8000"


class TestoMLXProviderExtraction:
    async def test_text_extraction_skips_ocr(self, monkeypatch):
        metadata_json = json.dumps({
            "authors": ["Fama", "French"],
            "year": 1993,
            "journal": "Journal of Financial Economics",
            "journal_abbrev": "JFE",
            "title": "Common risk factors",
            "confidence": 0.95,
        })

        async def mock_post(self, url, **kwargs):
            resp = httpx.Response(200, json=_chat_response(metadata_json))
            resp._request = httpx.Request("POST", url)
            return resp

        monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

        provider = oMLXProvider()
        content = PDFContent(text="A" * 200, first_page_image=None, path="/tmp/test.pdf")
        result = await provider.extract_metadata(content)
        assert result.authors == ["Fama", "French"]
        assert result.year == 1993

    async def test_ocr_then_parse(self, monkeypatch):
        metadata_json = json.dumps({
            "authors": ["Smith"],
            "year": 2024,
            "journal": "Nature",
            "title": "Test paper",
            "confidence": 0.9,
        })

        call_count = 0

        async def mock_post(self, url, **kwargs):
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                # OCR response
                return _make_response(200, _chat_response("Extracted OCR text from image"))
            else:
                # Metadata response
                return _make_response(200, _chat_response(metadata_json))

        def _make_response(status, data):
            resp = httpx.Response(status, json=data)
            resp._request = httpx.Request("POST", "http://localhost:8000/v1/chat/completions")
            return resp

        monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

        provider = oMLXProvider()
        content = PDFContent(text="short", first_page_image=b"fake-image", path="/tmp/test.pdf")
        result = await provider.extract_metadata(content)
        assert result.authors == ["Smith"]
        assert call_count == 2

    async def test_call_raw(self, monkeypatch):
        async def mock_post(self, url, **kwargs):
            resp = httpx.Response(200, json=_chat_response("Hello world"))
            resp._request = httpx.Request("POST", url)
            return resp

        monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

        provider = oMLXProvider()
        result = await provider.call_raw("Say hello")
        assert result == "Hello world"


class TestoMLXProviderErrors:
    async def test_connection_error(self, monkeypatch):
        async def mock_post(self, url, **kwargs):
            raise httpx.ConnectError("Connection refused")

        monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

        provider = oMLXProvider()
        content = PDFContent(text="A" * 200, first_page_image=None, path="/tmp/test.pdf")
        with pytest.raises(RuntimeError, match="Cannot connect to oMLX"):
            await provider.extract_metadata(content)

    async def test_model_not_found(self, monkeypatch):
        async def mock_post(self, url, **kwargs):
            resp = httpx.Response(404, text="model not found")
            resp._request = httpx.Request("POST", url)
            return resp

        monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

        provider = oMLXProvider()
        content = PDFContent(text="A" * 200, first_page_image=None, path="/tmp/test.pdf")
        with pytest.raises(RuntimeError, match="not found on oMLX"):
            await provider.extract_metadata(content)

    async def test_timeout(self, monkeypatch):
        async def mock_post(self, url, **kwargs):
            raise httpx.ReadTimeout("timed out")

        monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

        provider = oMLXProvider()
        content = PDFContent(text="A" * 200, first_page_image=None, path="/tmp/test.pdf")
        with pytest.raises(RuntimeError, match="timed out"):
            await provider.extract_metadata(content)

    async def test_empty_response(self, monkeypatch):
        async def mock_post(self, url, **kwargs):
            resp = httpx.Response(200, json=_chat_response(""))
            resp._request = httpx.Request("POST", url)
            return resp

        monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

        provider = oMLXProvider()
        content = PDFContent(text="A" * 200, first_page_image=None, path="/tmp/test.pdf")
        with pytest.raises(RuntimeError, match="empty response"):
            await provider.extract_metadata(content)


class TestoMLXReasoning:
    def test_reasoning_default_disables_thinking(self):
        provider = oMLXProvider()
        payload = provider._build_payload(
            "mlx-community/Qwen3.5-9B-MLX-4bit",
            [{"role": "user", "content": "test"}],
        )
        assert payload["chat_template_kwargs"]["enable_thinking"] is False

    def test_reasoning_none_disables_thinking(self):
        provider = oMLXProvider(reasoning=None)
        payload = provider._build_payload(
            "mlx-community/Qwen3.5-9B-MLX-4bit",
            [{"role": "user", "content": "test"}],
        )
        assert payload["chat_template_kwargs"]["enable_thinking"] is False

    def test_reasoning_true_enables_thinking(self):
        provider = oMLXProvider(reasoning=True)
        payload = provider._build_payload(
            "mlx-community/Qwen3.5-9B-MLX-4bit",
            [{"role": "user", "content": "test"}],
        )
        assert "chat_template_kwargs" not in payload

    def test_reasoning_non_qwen3_no_kwargs(self):
        provider = oMLXProvider()
        payload = provider._build_payload(
            "mlx-community/Llama-3.2-3B-Instruct-4bit",
            [{"role": "user", "content": "test"}],
        )
        assert "chat_template_kwargs" not in payload


class TestGetProvideroMLX:
    def test_get_provider_returns_omlx(self, monkeypatch, tmp_path):
        monkeypatch.setenv("NAMINGPAPER_AI_PROVIDER", "omlx")
        monkeypatch.delenv("NAMINGPAPER_MODEL_NAME", raising=False)
        monkeypatch.setattr("namingpaper.config.Path.home", lambda: tmp_path)
        from namingpaper.config import reset_settings
        reset_settings()

        from namingpaper.providers import get_provider
        provider = get_provider("omlx")
        assert isinstance(provider, oMLXProvider)
        assert provider.base_url == "http://localhost:8000"
        assert provider.text_model == "mlx-community/Qwen3.5-2B-MLX-4bit"

        reset_settings()

    def test_get_provider_passes_reasoning(self, monkeypatch, tmp_path):
        monkeypatch.setenv("NAMINGPAPER_AI_PROVIDER", "omlx")
        monkeypatch.delenv("NAMINGPAPER_MODEL_NAME", raising=False)
        monkeypatch.setattr("namingpaper.config.Path.home", lambda: tmp_path)
        from namingpaper.config import reset_settings
        reset_settings()

        from namingpaper.providers import get_provider
        provider = get_provider("omlx", reasoning=True)
        assert isinstance(provider, oMLXProvider)
        assert provider.reasoning is True

        provider2 = get_provider("omlx", reasoning=None)
        assert provider2.reasoning is None

        reset_settings()
