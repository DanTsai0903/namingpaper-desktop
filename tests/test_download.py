"""Tests for the download module."""

from datetime import datetime, timezone
from pathlib import Path

import pytest
from typer.testing import CliRunner

from namingpaper.download import DownloadSummary, download_papers, resolve_target_path
from namingpaper.models import Paper


def _make_paper(
    tmp_path: Path,
    *,
    paper_id: str = "abcd1234",
    category: str = "Finance",
    filename: str = "paper.pdf",
    create_file: bool = True,
) -> Paper:
    """Create a Paper with an optional real file on disk."""
    file_path = tmp_path / "library" / category / filename
    if create_file:
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_bytes(b"%PDF-fake-content-" + paper_id.encode())
    now = datetime.now(timezone.utc).isoformat()
    return Paper(
        id=paper_id,
        sha256=paper_id * 8,
        title=f"Test Paper {paper_id}",
        authors=["Author"],
        year=2024,
        journal="Test Journal",
        category=category,
        file_path=str(file_path),
        confidence=0.95,
        created_at=now,
        updated_at=now,
    )


class TestDownloadPapers:
    def test_structured_output(self, tmp_path):
        paper = _make_paper(tmp_path, category="Finance")
        out = tmp_path / "output"
        summary = download_papers([paper], out)

        assert summary.copied == 1
        assert (out / "Finance" / "paper.pdf").exists()

    def test_flat_output(self, tmp_path):
        paper = _make_paper(tmp_path, category="Finance")
        out = tmp_path / "output"
        summary = download_papers([paper], out, flat=True)

        assert summary.copied == 1
        assert (out / "paper.pdf").exists()
        assert not (out / "Finance").exists()

    def test_collision_skip(self, tmp_path):
        paper = _make_paper(tmp_path, category="Finance")
        out = tmp_path / "output"
        # First download
        download_papers([paper], out)
        # Second download should skip
        summary = download_papers([paper], out)

        assert summary.skipped == 1
        assert summary.copied == 0

    def test_collision_overwrite(self, tmp_path):
        paper = _make_paper(tmp_path, category="Finance")
        out = tmp_path / "output"
        download_papers([paper], out)
        summary = download_papers([paper], out, overwrite=True)

        assert summary.copied == 1
        assert summary.skipped == 0

    def test_missing_source_file(self, tmp_path):
        paper = _make_paper(tmp_path, create_file=False)
        out = tmp_path / "output"
        summary = download_papers([paper], out)

        assert summary.failed == 1
        assert paper.id in summary.failed_papers
        assert summary.copied == 0

    def test_unsorted_category(self, tmp_path):
        paper = _make_paper(tmp_path, category="Finance")
        paper.category = None
        out = tmp_path / "output"
        download_papers([paper], out)

        assert (out / "Unsorted" / "paper.pdf").exists()


class TestFlatModeCollision:
    def test_same_filename_different_category(self, tmp_path):
        p1 = _make_paper(tmp_path, paper_id="aaaa1111", category="Finance", filename="paper.pdf")
        p2 = _make_paper(tmp_path, paper_id="bbbb2222", category="Economics", filename="paper.pdf")
        out = tmp_path / "output"
        summary = download_papers([p1, p2], out, flat=True)

        assert summary.copied == 2
        assert (out / "paper.pdf").exists()
        assert (out / "paper_bbbb2222.pdf").exists()

    def test_no_collision_different_filenames(self, tmp_path):
        p1 = _make_paper(tmp_path, paper_id="aaaa1111", category="Finance", filename="a.pdf")
        p2 = _make_paper(tmp_path, paper_id="bbbb2222", category="Finance", filename="b.pdf")
        out = tmp_path / "output"
        summary = download_papers([p1, p2], out, flat=True)

        assert summary.copied == 2
        assert (out / "a.pdf").exists()
        assert (out / "b.pdf").exists()


class TestResolveTargetPath:
    def test_structured(self, tmp_path):
        paper = _make_paper(tmp_path, category="Finance", filename="test.pdf")
        out = tmp_path / "output"
        assert resolve_target_path(paper, out) == out / "Finance" / "test.pdf"

    def test_flat(self, tmp_path):
        paper = _make_paper(tmp_path, category="Finance", filename="test.pdf")
        out = tmp_path / "output"
        assert resolve_target_path(paper, out, flat=True) == out / "test.pdf"


class TestDownloadCLI:
    """Integration tests for the CLI download command."""

    @pytest.fixture
    def runner(self):
        return CliRunner()

    @pytest.fixture
    def populated_db(self, tmp_path):
        """Create a temporary database with a paper."""
        from namingpaper.database import Database

        db_path = tmp_path / "library.db"
        paper = _make_paper(tmp_path, paper_id="abcd1234", category="Finance")

        with Database(db_path=db_path) as db:
            db.create_paper(paper)

        return db_path, paper

    def test_no_selection_error(self, runner, tmp_path):
        from namingpaper.cli import app

        result = runner.invoke(app, ["download", "-o", str(tmp_path)])
        assert result.exit_code != 0
        assert "Specify paper IDs" in result.output

    def test_dry_run(self, runner, populated_db, tmp_path, monkeypatch):
        from namingpaper.cli import app
        from namingpaper import database as db_mod

        db_path, paper = populated_db
        monkeypatch.setattr(db_mod, "DEFAULT_DB_PATH", db_path)
        out = tmp_path / "output"

        result = runner.invoke(app, ["download", "--all", "-o", str(out)])
        assert result.exit_code == 0
        assert "Dry run mode" in result.output
        assert not out.exists()

    def test_execute(self, runner, populated_db, tmp_path, monkeypatch):
        from namingpaper.cli import app
        from namingpaper import database as db_mod

        db_path, paper = populated_db
        monkeypatch.setattr(db_mod, "DEFAULT_DB_PATH", db_path)
        out = tmp_path / "output"

        result = runner.invoke(app, ["download", "--all", "-o", str(out), "--execute"])
        assert result.exit_code == 0
        assert "Copied: 1" in result.output
        assert (out / "Finance" / "paper.pdf").exists()
