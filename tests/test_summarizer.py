"""Tests for the summarizer module."""

from unittest.mock import AsyncMock, MagicMock

import pytest

from namingpaper.models import PDFContent
from namingpaper.summarizer import analyze_paper, _parse_analysis_json, _parse_summary_json


class TestParseSummaryJson:
    def test_valid_json(self):
        response = '{"summary": "A great paper.", "keywords": ["finance", "risk"]}'
        summary, keywords = _parse_summary_json(response)
        assert summary == "A great paper."
        assert keywords == ["finance", "risk"]

    def test_json_in_code_block(self):
        response = '```json\n{"summary": "Test.", "keywords": ["a", "b"]}\n```'
        summary, keywords = _parse_summary_json(response)
        assert summary == "Test."
        assert keywords == ["a", "b"]

    def test_keywords_lowercased(self):
        response = '{"summary": "Test.", "keywords": ["Finance", "RISK"]}'
        summary, keywords = _parse_summary_json(response)
        assert keywords == ["finance", "risk"]

    def test_partial_result_no_keywords(self):
        response = '{"summary": "Just a summary."}'
        summary, keywords = _parse_summary_json(response)
        assert summary == "Just a summary."
        assert keywords == []

    def test_partial_result_no_summary(self):
        response = '{"keywords": ["a", "b"]}'
        summary, keywords = _parse_summary_json(response)
        assert summary is None
        assert keywords == ["a", "b"]

    def test_invalid_json(self):
        response = "not json at all"
        summary, keywords = _parse_summary_json(response)
        assert summary is None
        assert keywords == []

    def test_empty_response(self):
        summary, keywords = _parse_summary_json("")
        assert summary is None
        assert keywords == []


class TestParseAnalysisJson:
    def test_valid_json(self):
        response = """{
            "authors": ["Fama", "French"],
            "authors_full": ["Eugene F. Fama", "Kenneth R. French"],
            "year": 1993,
            "journal": "Journal of Financial Economics",
            "journal_abbrev": "JFE",
            "title": "Common risk factors",
            "confidence": 0.95,
            "summary": "A classic factor-pricing paper.",
            "keywords": ["Finance", "Risk Factors"]
        }"""
        metadata, summary, keywords = _parse_analysis_json(response)
        assert metadata.authors == ["Fama", "French"]
        assert metadata.journal_abbrev == "JFE"
        assert summary == "A classic factor-pricing paper."
        assert keywords == ["finance", "risk factors"]

    def test_invalid_json_raises(self):
        with pytest.raises(RuntimeError, match="parse paper analysis"):
            _parse_analysis_json("not json")


class TestAnalyzePaper:
    async def test_single_call_returns_metadata_and_summary(self):
        provider = MagicMock()
        provider._truncate_text.return_value = "paper text"
        provider.call_raw = AsyncMock(return_value="""{
            "authors": ["Smith"],
            "authors_full": ["John Smith"],
            "year": 2024,
            "journal": "Nature",
            "journal_abbrev": "Nat",
            "title": "Test paper",
            "confidence": 0.9,
            "summary": "This paper tests something.",
            "keywords": ["Science", "Testing"]
        }""")
        content = PDFContent(text="A" * 500, first_page_image=None, path="/tmp/test.pdf")

        metadata, summary, keywords = await analyze_paper(content, provider)

        provider.call_raw.assert_awaited_once()
        assert metadata.title == "Test paper"
        assert summary == "This paper tests something."
        assert keywords == ["science", "testing"]
