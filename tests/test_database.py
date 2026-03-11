"""Tests for the database layer."""

import json
from datetime import datetime, timezone
from pathlib import Path

import pytest

from namingpaper.database import Database, compute_file_hash, generate_paper_id
from namingpaper.models import Paper, SearchFilter


@pytest.fixture
def db(tmp_path):
    """Provide a temporary database."""
    db_path = tmp_path / "test.db"
    database = Database(db_path=db_path)
    database.open()
    yield database
    database.close()


@pytest.fixture
def sample_paper():
    """Provide a sample paper record."""
    now = datetime.now(timezone.utc).isoformat()
    return Paper(
        id="abcd1234",
        sha256="a" * 64,
        title="Common risk factors in the returns on stocks and bonds",
        authors=["Fama", "French"],
        authors_full=["Eugene F. Fama", "Kenneth R. French"],
        year=1993,
        journal="Journal of Financial Economics",
        journal_abbrev="JFE",
        summary="Identifies three common risk factors in stock returns.",
        keywords=["asset pricing", "risk factors", "size effect"],
        category="Finance/Asset Pricing",
        file_path="/tmp/papers/fama_french_1993.pdf",
        confidence=0.95,
        created_at=now,
        updated_at=now,
    )


class TestDatabaseInit:
    def test_creates_db_file(self, tmp_path):
        db_path = tmp_path / "subdir" / "lib.db"
        with Database(db_path=db_path) as db:
            assert db_path.exists()

    def test_reopens_existing_db(self, tmp_path, sample_paper):
        db_path = tmp_path / "lib.db"
        with Database(db_path=db_path) as db:
            db.create_paper(sample_paper)

        with Database(db_path=db_path) as db:
            paper = db.get_paper("abcd1234")
            assert paper is not None
            assert paper.title == sample_paper.title

    def test_schema_version_set(self, db):
        version = db._get_schema_version()
        assert version == 1


class TestCRUD:
    def test_create_and_get(self, db, sample_paper):
        db.create_paper(sample_paper)
        result = db.get_paper("abcd1234")
        assert result is not None
        assert result.title == sample_paper.title
        assert result.authors == ["Fama", "French"]
        assert result.year == 1993
        assert result.keywords == ["asset pricing", "risk factors", "size effect"]

    def test_get_nonexistent(self, db):
        assert db.get_paper("nonexistent") is None

    def test_create_minimal(self, db):
        now = datetime.now(timezone.utc).isoformat()
        paper = Paper(
            id="min12345",
            sha256="b" * 64,
            title="Minimal paper",
            authors=["Smith"],
            year=2020,
            journal="Some Journal",
            file_path="/tmp/minimal.pdf",
            created_at=now,
            updated_at=now,
        )
        db.create_paper(paper)
        result = db.get_paper("min12345")
        assert result is not None
        assert result.summary is None
        assert result.keywords == []
        assert result.journal_abbrev is None

    def test_update(self, db, sample_paper):
        db.create_paper(sample_paper)
        db.update_paper("abcd1234", category="Finance/Empirical", summary="Updated summary")
        result = db.get_paper("abcd1234")
        assert result.category == "Finance/Empirical"
        assert result.summary == "Updated summary"

    def test_delete(self, db, sample_paper):
        db.create_paper(sample_paper)
        assert db.delete_paper("abcd1234")
        assert db.get_paper("abcd1234") is None

    def test_delete_nonexistent(self, db):
        assert not db.delete_paper("nonexistent")


class TestDuplicate:
    def test_duplicate_hash_detected(self, db, sample_paper):
        db.create_paper(sample_paper)
        existing = db.get_paper_by_hash("a" * 64)
        assert existing is not None
        assert existing.id == "abcd1234"

    def test_unique_hash_not_found(self, db, sample_paper):
        db.create_paper(sample_paper)
        assert db.get_paper_by_hash("c" * 64) is None


class TestFTSSearch:
    def test_search_by_title(self, db, sample_paper):
        db.create_paper(sample_paper)
        results = db.search(query="risk factors")
        assert len(results) == 1
        assert results[0].id == "abcd1234"

    def test_search_by_author(self, db, sample_paper):
        db.create_paper(sample_paper)
        results = db.search(query="Fama")
        assert len(results) == 1

    def test_search_no_match(self, db, sample_paper):
        db.create_paper(sample_paper)
        results = db.search(query="quantum computing")
        assert len(results) == 0

    def test_fts_updated_after_update(self, db, sample_paper):
        db.create_paper(sample_paper)
        db.update_paper("abcd1234", summary="Now about quantum computing")
        results = db.search(query="quantum computing")
        assert len(results) == 1

    def test_fts_removed_after_delete(self, db, sample_paper):
        db.create_paper(sample_paper)
        db.delete_paper("abcd1234")
        results = db.search(query="risk factors")
        assert len(results) == 0


class TestFilteredSearch:
    @pytest.fixture(autouse=True)
    def setup_papers(self, db):
        now = datetime.now(timezone.utc).isoformat()
        papers = [
            Paper(id="p1", sha256="1" * 64, title="Paper one", authors=["Fama"],
                  year=1993, journal="JFE", journal_abbrev="JFE",
                  category="Finance/Asset Pricing", file_path="/p1.pdf",
                  created_at=now, updated_at=now),
            Paper(id="p2", sha256="2" * 64, title="Paper two", authors=["Smith"],
                  year=2020, journal="AER", journal_abbrev="AER",
                  category="Economics/Macro", file_path="/p2.pdf",
                  created_at=now, updated_at=now),
            Paper(id="p3", sha256="3" * 64, title="Paper three", authors=["Fama", "French"],
                  year=2015, journal="JFE", journal_abbrev="JFE",
                  category="Finance/Asset Pricing", file_path="/p3.pdf",
                  created_at=now, updated_at=now),
        ]
        for p in papers:
            db.create_paper(p)

    def test_filter_by_author(self, db):
        results = db.search(filters=SearchFilter(author="Fama"))
        assert len(results) == 2

    def test_filter_by_year_range(self, db):
        results = db.search(filters=SearchFilter(year_from=2010, year_to=2024))
        assert len(results) == 2

    def test_filter_by_journal(self, db):
        results = db.search(filters=SearchFilter(journal="JFE"))
        assert len(results) == 2

    def test_filter_by_category(self, db):
        results = db.search(filters=SearchFilter(category="Economics/Macro"))
        assert len(results) == 1

    def test_combined_fts_and_filter(self, db):
        results = db.search(query="Paper", filters=SearchFilter(journal="JFE"))
        assert len(results) == 2


class TestHelpers:
    def test_compute_file_hash(self, tmp_path):
        f = tmp_path / "test.pdf"
        f.write_bytes(b"fake pdf content")
        h = compute_file_hash(f)
        assert len(h) == 64

    def test_generate_paper_id(self):
        pid = generate_paper_id("abcdef1234567890" * 4)
        assert pid == "abcdef12"
        assert len(pid) == 8


class TestListPapers:
    def test_list_with_limit(self, db, sample_paper):
        db.create_paper(sample_paper)
        results = db.list_papers(limit=10)
        assert len(results) == 1

    def test_list_empty(self, db):
        results = db.list_papers()
        assert results == []
