"""End-to-end test for library operations: add, search, list, info, remove."""

from datetime import datetime, timezone
from pathlib import Path

import pytest

from namingpaper.database import Database, compute_file_hash, generate_paper_id
from namingpaper.library import remove_paper, search_library, sync_library
from namingpaper.models import Paper, SearchFilter


@pytest.fixture
def db(tmp_path):
    db_path = tmp_path / "e2e.db"
    database = Database(db_path=db_path)
    database.open()
    yield database
    database.close()


@pytest.fixture
def papers_dir(tmp_path):
    d = tmp_path / "Papers"
    d.mkdir()
    (d / "Unsorted").mkdir()
    (d / "Finance" / "Asset Pricing").mkdir(parents=True)
    return d


@pytest.fixture
def fake_pdf(tmp_path):
    f = tmp_path / "test_paper.pdf"
    f.write_bytes(b"%PDF-1.4 fake paper content for testing hash")
    return f


def _make_paper(fake_pdf: Path, papers_dir: Path) -> Paper:
    """Create a paper record simulating the add workflow."""
    sha256 = compute_file_hash(fake_pdf)
    now = datetime.now(timezone.utc).isoformat()
    return Paper(
        id=generate_paper_id(sha256),
        sha256=sha256,
        title="Common risk factors in the returns on stocks and bonds",
        authors=["Fama", "French"],
        authors_full=["Eugene F. Fama", "Kenneth R. French"],
        year=1993,
        journal="Journal of Financial Economics",
        journal_abbrev="JFE",
        summary="Identifies three common risk factors in stock returns.",
        keywords=["asset pricing", "risk factors", "size effect"],
        category="Finance/Asset Pricing",
        file_path=str(papers_dir / "Finance" / "Asset Pricing" / "fama_french.pdf"),
        confidence=0.95,
        created_at=now,
        updated_at=now,
    )


class TestLibraryE2E:
    def test_full_lifecycle(self, db, papers_dir, fake_pdf):
        """Add → search → list → info → remove lifecycle."""
        paper = _make_paper(fake_pdf, papers_dir)

        # 1. Add (simulate by directly inserting)
        db.create_paper(paper)
        assert db.get_paper(paper.id) is not None

        # 2. Search by keyword
        results = search_library(db, query="risk factors")
        assert len(results) == 1
        assert results[0].id == paper.id

        # 3. Search with filter
        results = search_library(
            db, filters=SearchFilter(author="Fama", year_from=1990, year_to=2000)
        )
        assert len(results) == 1

        # 4. List
        all_papers = db.list_papers()
        assert len(all_papers) == 1

        # 5. Info (get by id)
        info = db.get_paper(paper.id)
        assert info.title == paper.title
        assert info.keywords == ["asset pricing", "risk factors", "size effect"]

        # 6. Remove
        removed = remove_paper(db, paper.id)
        assert removed is not None
        assert db.get_paper(paper.id) is None

    def test_duplicate_detection(self, db, papers_dir, fake_pdf):
        paper = _make_paper(fake_pdf, papers_dir)
        db.create_paper(paper)

        # Same hash should be found
        existing = db.get_paper_by_hash(paper.sha256)
        assert existing is not None
        assert existing.id == paper.id

    def test_sync_detects_missing(self, db, papers_dir, fake_pdf):
        paper = _make_paper(fake_pdf, papers_dir)
        db.create_paper(paper)

        # File doesn't actually exist at file_path
        untracked, missing = sync_library(db, papers_dir)
        assert len(missing) == 1
        assert missing[0].id == paper.id

    def test_sync_detects_untracked(self, db, papers_dir):
        # Put a PDF on disk that's not in DB
        pdf = papers_dir / "Finance" / "Asset Pricing" / "untracked.pdf"
        pdf.write_bytes(b"%PDF-1.4 untracked")

        untracked, missing = sync_library(db, papers_dir)
        assert len(untracked) == 1
        assert untracked[0].name == "untracked.pdf"

    def test_remove_with_file_delete(self, db, papers_dir, fake_pdf):
        paper = _make_paper(fake_pdf, papers_dir)

        # Place the file at the expected location
        dest = Path(paper.file_path)
        dest.parent.mkdir(parents=True, exist_ok=True)
        import shutil
        shutil.copy2(fake_pdf, dest)

        db.create_paper(paper)
        assert dest.exists()

        remove_paper(db, paper.id, delete_file=True)
        assert not dest.exists()
        assert db.get_paper(paper.id) is None
