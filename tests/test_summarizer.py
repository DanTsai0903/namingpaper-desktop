"""Tests for the summarizer module."""

from namingpaper.summarizer import _parse_summary_json


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
