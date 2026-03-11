"""Tests for Paper, SearchFilter models and papers_dir config."""

from datetime import datetime, timezone
from pathlib import Path

import pytest

from namingpaper.models import Paper, SearchFilter
from namingpaper.config import Settings


class TestPaperModel:
    def test_full_paper(self):
        now = datetime.now(timezone.utc).isoformat()
        paper = Paper(
            id="abc12345",
            sha256="a" * 64,
            title="Test Paper",
            authors=["Smith", "Jones"],
            authors_full=["John Smith", "Jane Jones"],
            year=2023,
            journal="Journal of Finance",
            journal_abbrev="JF",
            summary="A test paper about finance.",
            keywords=["finance", "testing"],
            category="Finance",
            file_path="/tmp/test.pdf",
            confidence=0.9,
            created_at=now,
            updated_at=now,
        )
        assert paper.authors == ["Smith", "Jones"]
        assert paper.keywords == ["finance", "testing"]

    def test_minimal_paper(self):
        now = datetime.now(timezone.utc).isoformat()
        paper = Paper(
            id="min00000",
            sha256="b" * 64,
            title="Minimal",
            authors=["Smith"],
            year=2020,
            journal="Some Journal",
            file_path="/tmp/min.pdf",
            created_at=now,
            updated_at=now,
        )
        assert paper.summary is None
        assert paper.keywords == []
        assert paper.journal_abbrev is None
        assert paper.category is None


class TestSearchFilter:
    def test_defaults(self):
        f = SearchFilter()
        assert f.author is None
        assert f.year_from is None
        assert f.year_to is None
        assert f.journal is None
        assert f.category is None
        assert f.smart is False

    def test_with_values(self):
        f = SearchFilter(author="Fama", year_from=2020, year_to=2024, journal="JFE")
        assert f.author == "Fama"
        assert f.year_from == 2020
        assert f.year_to == 2024


class TestPapersDirConfig:
    def test_default_papers_dir(self):
        settings = Settings()
        assert settings.papers_dir == Path.home() / "Papers"

    def test_custom_papers_dir(self, monkeypatch):
        monkeypatch.setenv("NAMINGPAPER_PAPERS_DIR", "/tmp/my_papers")
        settings = Settings()
        assert settings.papers_dir == Path("/tmp/my_papers")
