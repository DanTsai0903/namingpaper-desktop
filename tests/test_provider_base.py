"""Tests for AIProvider helper methods."""

from namingpaper.models import PDFContent
from namingpaper.providers.base import AIProvider


class DummyProvider(AIProvider):
    async def extract_metadata(self, content: PDFContent):
        raise NotImplementedError


class TestAIProviderHelpers:
    def test_image_used_when_text_is_short(self):
        provider = DummyProvider()
        content = PDFContent(
            text="short text",
            first_page_image=b"fake-image",
            path="/tmp/test.pdf",
        )

        assert provider._should_include_image(content) is True

    def test_image_skipped_when_text_is_usable(self):
        provider = DummyProvider()
        content = PDFContent(
            text="A" * 200,
            first_page_image=b"fake-image",
            path="/tmp/test.pdf",
        )

        assert provider._should_include_image(content) is False

    def test_image_skipped_when_missing(self):
        provider = DummyProvider()
        content = PDFContent(
            text="A" * 200,
            first_page_image=None,
            path="/tmp/test.pdf",
        )

        assert provider._should_include_image(content) is False
