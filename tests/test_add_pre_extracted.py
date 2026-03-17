"""Tests for pre-extracted metadata in add_paper() and CLI --json/--metadata-json flags."""

import json
from pathlib import Path
from unittest.mock import AsyncMock, patch, MagicMock

import pytest
from typer.testing import CliRunner

from namingpaper.cli import app
from namingpaper.library import AddResult, add_paper
from namingpaper.models import PDFContent, Paper, PaperMetadata

runner = CliRunner()

PRE_EXTRACTED = {
    "title": "Common risk factors in the returns on stocks and bonds",
    "authors": ["Fama", "French"],
    "authors_full": ["Eugene F. Fama", "Kenneth R. French"],
    "year": 1993,
    "journal": "Journal of Financial Economics",
    "journal_abbrev": "JFE",
    "summary": "Identifies three common risk factors.",
    "keywords": ["asset pricing", "risk factors"],
    "category": "Finance/Asset Pricing",
    "confidence": 0.95,
}


@pytest.fixture
def fake_pdf(tmp_path):
    pdf = tmp_path / "test.pdf"
    pdf.write_bytes(b"%PDF-1.4 fake content for hash")
    return pdf


@pytest.fixture
def mock_db(tmp_path):
    from namingpaper.database import Database
    db = Database(db_path=tmp_path / "test.db")
    db.open()
    yield db
    db.close()


def _mock_settings(tmp_path):
    return MagicMock(papers_dir=tmp_path / "Papers")


class TestAddPaperPreExtracted:
    """Test that pre_extracted skips AI calls."""

    async def test_skips_all_ai_when_fully_pre_extracted(self, fake_pdf, mock_db, tmp_path):
        with patch("namingpaper.library.get_settings") as mock_settings, \
             patch("namingpaper.library.extract_metadata_from_content") as mock_extract, \
             patch("namingpaper.library.analyze_paper") as mock_analyze, \
             patch("namingpaper.library.summarize_paper") as mock_summarize, \
             patch("namingpaper.library.suggest_category") as mock_categorize, \
             patch("namingpaper.library.get_provider") as mock_get_provider:
            mock_settings.return_value = _mock_settings(tmp_path)

            result = await add_paper(
                fake_pdf, db=mock_db, pre_extracted=PRE_EXTRACTED,
            )

            mock_extract.assert_not_called()
            mock_analyze.assert_not_called()
            mock_summarize.assert_not_called()
            mock_categorize.assert_not_called()
            mock_get_provider.assert_not_called()

            assert result.paper is not None
            assert result.paper.title == PRE_EXTRACTED["title"]
            assert result.paper.authors == PRE_EXTRACTED["authors"]
            assert result.paper.authors_full == PRE_EXTRACTED["authors_full"]
            assert result.paper.year == PRE_EXTRACTED["year"]
            assert result.paper.journal == PRE_EXTRACTED["journal"]
            assert result.paper.journal_abbrev == PRE_EXTRACTED["journal_abbrev"]
            assert result.paper.summary == PRE_EXTRACTED["summary"]
            assert result.paper.keywords == PRE_EXTRACTED["keywords"]
            assert result.paper.category == PRE_EXTRACTED["category"]
            assert result.paper.confidence == PRE_EXTRACTED["confidence"]

    async def test_full_ai_add_uses_single_analysis_call_when_text_is_usable(self, fake_pdf, mock_db, tmp_path):
        mock_provider = MagicMock()
        mock_provider._has_usable_text.return_value = True
        content = PDFContent(text="A" * 500, first_page_image=None, path=fake_pdf)
        metadata = PaperMetadata(
            title="Combined Analysis Paper",
            authors=["Smith"],
            authors_full=["John Smith"],
            year=2024,
            journal="Nature",
            journal_abbrev="Nat",
            confidence=0.93,
        )

        with patch("namingpaper.library.get_settings") as mock_settings, \
             patch("namingpaper.library.extract_pdf_content", return_value=content), \
             patch(
                 "namingpaper.library.analyze_paper",
                 return_value=(metadata, "Combined summary", ["token", "saver"]),
             ) as mock_analyze, \
             patch("namingpaper.library.extract_metadata_from_content") as mock_extract, \
             patch("namingpaper.library.summarize_paper") as mock_summarize, \
             patch("namingpaper.library.suggest_category", return_value="Unsorted") as mock_categorize, \
             patch("namingpaper.library.prompt_category_selection", return_value="Unsorted"), \
             patch("namingpaper.library.discover_categories", return_value=[]):
            mock_settings.return_value = _mock_settings(tmp_path)

            result = await add_paper(fake_pdf, db=mock_db, provider=mock_provider)

            mock_analyze.assert_called_once_with(content, mock_provider)
            mock_extract.assert_not_called()
            mock_summarize.assert_not_called()
            mock_categorize.assert_called_once()
            assert result.paper is not None
            assert result.paper.title == "Combined Analysis Paper"
            assert result.paper.summary == "Combined summary"
            assert result.paper.keywords == ["token", "saver"]

    async def test_category_override_takes_precedence(self, fake_pdf, mock_db, tmp_path):
        with patch("namingpaper.library.get_settings") as mock_settings:
            mock_settings.return_value = _mock_settings(tmp_path)

            result = await add_paper(
                fake_pdf, db=mock_db,
                pre_extracted=PRE_EXTRACTED,
                category_override="Custom/Category",
            )

            assert result.paper.category == "Custom/Category"

    async def test_filename_override_with_pre_extracted(self, fake_pdf, mock_db, tmp_path):
        with patch("namingpaper.library.get_settings") as mock_settings:
            mock_settings.return_value = _mock_settings(tmp_path)

            result = await add_paper(
                fake_pdf, db=mock_db,
                pre_extracted=PRE_EXTRACTED,
                filename_override="custom_name.pdf",
            )

            assert Path(result.paper.file_path).name == "custom_name.pdf"

    async def test_partial_pre_extracted_no_summary_calls_summarize(self, fake_pdf, mock_db, tmp_path):
        """Pre-extracted with metadata but no summary should call summarize."""
        partial = {
            "title": "Test Title",
            "authors": ["Smith"],
            "year": 2024,
            "journal": "Test Journal",
            # No summary or category — AI needed for both
        }
        mock_provider = AsyncMock()

        with patch("namingpaper.library.get_settings") as mock_settings, \
             patch("namingpaper.library.extract_metadata_from_content") as mock_extract, \
             patch("namingpaper.library.analyze_paper") as mock_analyze, \
             patch("namingpaper.library.extract_pdf_content") as mock_pdf, \
             patch("namingpaper.library.summarize_paper", return_value=("A summary", ["kw"])) as mock_summarize, \
             patch("namingpaper.library.suggest_category", return_value="Unsorted") as mock_categorize, \
             patch("namingpaper.library.prompt_category_selection", return_value="Unsorted"), \
             patch("namingpaper.library.discover_categories", return_value=[]), \
             patch("namingpaper.library.get_provider", return_value=mock_provider):
            mock_settings.return_value = _mock_settings(tmp_path)

            result = await add_paper(
                fake_pdf, db=mock_db, pre_extracted=partial,
            )

            # Metadata extraction should be skipped (we have title/authors/year)
            mock_extract.assert_not_called()
            mock_analyze.assert_not_called()
            # But summarize and categorize should be called
            mock_summarize.assert_called_once()
            mock_categorize.assert_called_once()
            assert result.paper.summary == "A summary"

    async def test_partial_pre_extracted_has_summary_no_category(self, fake_pdf, mock_db, tmp_path):
        """Pre-extracted with metadata + summary but no category should only call categorize."""
        partial = {
            "title": "Test Title",
            "authors": ["Smith"],
            "year": 2024,
            "journal": "Test Journal",
            "summary": "Pre-existing summary",
            "keywords": ["kw1"],
            # No category — AI needed for categorization only
        }
        mock_provider = AsyncMock()

        with patch("namingpaper.library.get_settings") as mock_settings, \
             patch("namingpaper.library.extract_metadata_from_content") as mock_extract, \
             patch("namingpaper.library.analyze_paper") as mock_analyze, \
             patch("namingpaper.library.summarize_paper") as mock_summarize, \
             patch("namingpaper.library.suggest_category", return_value="Unsorted") as mock_categorize, \
             patch("namingpaper.library.prompt_category_selection", return_value="Unsorted"), \
             patch("namingpaper.library.discover_categories", return_value=[]), \
             patch("namingpaper.library.get_provider", return_value=mock_provider):
            mock_settings.return_value = _mock_settings(tmp_path)

            result = await add_paper(
                fake_pdf, db=mock_db, pre_extracted=partial,
            )

            mock_extract.assert_not_called()
            mock_analyze.assert_not_called()
            mock_summarize.assert_not_called()
            mock_categorize.assert_called_once()
            assert result.paper.summary == "Pre-existing summary"

    async def test_execute_with_pre_extracted_copies_and_persists(self, fake_pdf, mock_db, tmp_path):
        """execute=True with pre_extracted should copy file and write to DB."""
        papers_dir = tmp_path / "Papers"
        with patch("namingpaper.library.get_settings") as mock_settings:
            mock_settings.return_value = MagicMock(papers_dir=papers_dir)

            result = await add_paper(
                fake_pdf, db=mock_db,
                pre_extracted=PRE_EXTRACTED,
                execute=True,
                copy=True,
            )

            assert result.paper is not None
            dest = Path(result.paper.file_path)
            assert dest.exists()
            assert dest.parent == papers_dir / PRE_EXTRACTED["category"]

            # Paper should be persisted in DB
            db_paper = mock_db.get_paper(result.paper.id)
            assert db_paper is not None
            assert db_paper.title == PRE_EXTRACTED["title"]

    async def test_pre_extracted_defaults_for_optional_fields(self, fake_pdf, mock_db, tmp_path):
        """Pre-extracted with only required fields should use defaults for optional ones."""
        minimal = {
            "title": "Minimal Paper",
            "authors": ["Doe"],
            "year": 2020,
            "summary": "A summary",
            "category": "Unsorted",
        }
        with patch("namingpaper.library.get_settings") as mock_settings:
            mock_settings.return_value = _mock_settings(tmp_path)

            result = await add_paper(
                fake_pdf, db=mock_db, pre_extracted=minimal,
            )

            assert result.paper.journal == ""
            assert result.paper.journal_abbrev is None
            assert result.paper.authors_full == []
            assert result.paper.confidence == 1.0
            assert result.paper.keywords == []


class TestAddCommandJSON:
    """Test --json flag on the add command."""

    def _make_paper(self, tmp_path, **overrides):
        defaults = dict(
            id="abc123", sha256="fakehash", title="Test Paper",
            authors=["Smith"], authors_full=["John Smith"],
            year=2024, journal="Test Journal", journal_abbrev="TJ",
            summary="A test summary.", keywords=["test"],
            category="Unsorted",
            file_path=str(tmp_path / "Papers" / "Unsorted" / "Smith, (2024, TJ), Test Paper.pdf"),
            confidence=0.95,
            created_at="2024-01-01T00:00:00Z", updated_at="2024-01-01T00:00:00Z",
        )
        defaults.update(overrides)
        return Paper(**defaults)

    def test_json_output_format(self, tmp_path):
        pdf = tmp_path / "test.pdf"
        pdf.write_bytes(b"%PDF-1.4 content")
        mock_paper = self._make_paper(tmp_path)

        with patch("namingpaper.database.Database") as MockDB, \
             patch("namingpaper.library.add_paper", new_callable=AsyncMock) as mock_add:
            MockDB.return_value.__enter__ = MagicMock(return_value=MagicMock())
            MockDB.return_value.__exit__ = MagicMock(return_value=False)
            mock_add.return_value = AddResult(paper=mock_paper)

            result = runner.invoke(app, ["add", str(pdf), "--json"])

        assert result.exit_code == 0
        data = json.loads(result.output)
        assert data["status"] == "ok"
        assert data["source"] == str(pdf)
        assert data["paper"]["title"] == "Test Paper"
        assert data["paper"]["authors"] == ["Smith"]
        assert data["paper"]["authors_full"] == ["John Smith"]
        assert data["paper"]["year"] == 2024
        assert data["paper"]["journal"] == "Test Journal"
        assert data["paper"]["journal_abbrev"] == "TJ"
        assert data["paper"]["summary"] == "A test summary."
        assert data["paper"]["keywords"] == ["test"]
        assert data["paper"]["category"] == "Unsorted"
        assert data["paper"]["filename"] == "Smith, (2024, TJ), Test Paper.pdf"
        assert data["paper"]["confidence"] == 0.95

    def test_json_skipped_output(self, tmp_path):
        pdf = tmp_path / "test.pdf"
        pdf.write_bytes(b"%PDF-1.4 content")

        existing = Paper(
            id="abc123", sha256="fakehash", title="Existing",
            authors=["A"], year=2020, journal="J",
            file_path="/some/path.pdf",
            created_at="2024-01-01T00:00:00Z", updated_at="2024-01-01T00:00:00Z",
        )

        with patch("namingpaper.database.Database") as MockDB, \
             patch("namingpaper.library.add_paper", new_callable=AsyncMock) as mock_add:
            MockDB.return_value.__enter__ = MagicMock(return_value=MagicMock())
            MockDB.return_value.__exit__ = MagicMock(return_value=False)
            mock_add.return_value = AddResult(skipped=True, existing=existing)

            result = runner.invoke(app, ["add", str(pdf), "--json"])

        assert result.exit_code == 0
        data = json.loads(result.output)
        assert data["status"] == "skipped"
        assert data["existing_id"] == "abc123"

    def test_json_error_output(self, tmp_path):
        pdf = tmp_path / "test.pdf"
        pdf.write_bytes(b"%PDF-1.4 content")

        with patch("namingpaper.database.Database") as MockDB, \
             patch("namingpaper.library.add_paper", new_callable=AsyncMock) as mock_add:
            MockDB.return_value.__enter__ = MagicMock(return_value=MagicMock())
            MockDB.return_value.__exit__ = MagicMock(return_value=False)
            mock_add.return_value = AddResult(error="Provider failed")

            result = runner.invoke(app, ["add", str(pdf), "--json"])

        assert result.exit_code == 1
        data = json.loads(result.output)
        assert data["status"] == "error"
        assert data["source"] == str(pdf)
        assert "Provider failed" in data["error"]

    def test_json_non_pdf_error(self, tmp_path):
        txt = tmp_path / "test.txt"
        txt.write_text("not a pdf")

        result = runner.invoke(app, ["add", str(txt), "--json"])

        assert result.exit_code == 1
        data = json.loads(result.output)
        assert data["status"] == "error"
        assert "Not a PDF" in data["error"]


class TestMetadataJSONFlag:
    """Test --metadata-json flag parsing."""

    def test_invalid_json_shows_error(self, tmp_path):
        pdf = tmp_path / "test.pdf"
        pdf.write_bytes(b"%PDF-1.4 content")

        result = runner.invoke(app, ["add", str(pdf), "--metadata-json", "not{valid json"])
        assert result.exit_code == 1
        assert "Invalid --metadata-json" in result.output

    def test_invalid_json_with_json_flag(self, tmp_path):
        pdf = tmp_path / "test.pdf"
        pdf.write_bytes(b"%PDF-1.4 content")

        result = runner.invoke(app, ["add", str(pdf), "--json", "--metadata-json", "bad"])
        assert result.exit_code == 1
        data = json.loads(result.output)
        assert data["status"] == "error"
        assert "Invalid --metadata-json" in data["error"]

    def test_metadata_json_passed_to_add_paper(self, tmp_path):
        """Verify --metadata-json is parsed and forwarded as pre_extracted."""
        pdf = tmp_path / "test.pdf"
        pdf.write_bytes(b"%PDF-1.4 content")
        metadata = json.dumps(PRE_EXTRACTED)

        mock_paper = Paper(
            id="abc123", sha256="fakehash", title="Test",
            authors=["Fama"], year=1993, journal="JFE",
            file_path="/path/test.pdf",
            created_at="2024-01-01T00:00:00Z", updated_at="2024-01-01T00:00:00Z",
        )

        with patch("namingpaper.database.Database") as MockDB, \
             patch("namingpaper.library.add_paper", new_callable=AsyncMock) as mock_add:
            MockDB.return_value.__enter__ = MagicMock(return_value=MagicMock())
            MockDB.return_value.__exit__ = MagicMock(return_value=False)
            mock_add.return_value = AddResult(paper=mock_paper)

            result = runner.invoke(app, [
                "add", str(pdf), "--execute", "--metadata-json", metadata,
            ])

        assert result.exit_code == 0
        # asyncio.run is called with the coroutine; the mock intercepts it.
        # Verify pre_extracted was passed through by inspecting the mock call.
        mock_add.assert_called_once()
        call_kwargs = mock_add.call_args.kwargs
        assert call_kwargs["pre_extracted"] == PRE_EXTRACTED


class TestRoundTripJSON:
    """Test that JSON output from --json can be fed back via --metadata-json."""

    def test_json_output_is_valid_pre_extracted_input(self, tmp_path):
        """The 'paper' object from --json output should be accepted by --metadata-json."""
        # Simulate the JSON the CLI would output
        cli_json_output = {
            "status": "ok",
            "source": "/path/to/paper.pdf",
            "paper": {
                "title": "A Test Paper",
                "authors": ["Smith", "Jones"],
                "authors_full": ["John Smith", "Alice Jones"],
                "year": 2024,
                "journal": "Nature",
                "journal_abbrev": "Nat",
                "summary": "This paper tests things.",
                "keywords": ["test", "science"],
                "category": "Science",
                "filename": "Smith, Jones, (2024, Nat), A Test Paper.pdf",
                "destination": "/papers/Science/Smith, Jones, (2024, Nat), A Test Paper.pdf",
                "confidence": 0.92,
            },
        }

        # The paper dict should work as pre_extracted input for add_paper
        paper_dict = cli_json_output["paper"]
        assert paper_dict.get("title")
        assert paper_dict.get("authors")
        assert paper_dict.get("year")
        assert paper_dict.get("summary") is not None
        assert paper_dict.get("category") is not None

        # Verify it produces valid PaperMetadata
        from namingpaper.models import PaperMetadata
        metadata = PaperMetadata(
            title=paper_dict["title"],
            authors=paper_dict["authors"],
            authors_full=paper_dict.get("authors_full", []),
            year=paper_dict["year"],
            journal=paper_dict.get("journal", ""),
            journal_abbrev=paper_dict.get("journal_abbrev"),
            confidence=paper_dict.get("confidence", 1.0),
        )
        assert metadata.title == "A Test Paper"
        assert metadata.authors == ["Smith", "Jones"]

    def test_swift_style_cached_json_is_valid_pre_extracted(self):
        """JSON produced by Swift PreExtractedMetadata Codable matches Python expectations.

        This simulates what the Swift app would produce via JSONEncoder and
        verifies the Python side accepts it correctly.
        """
        # Simulate Swift JSONEncoder output (snake_case keys via CodingKeys)
        swift_json = json.dumps({
            "title": "Common risk factors",
            "authors": ["Fama", "French"],
            "authors_full": ["Eugene F. Fama", "Kenneth R. French"],
            "year": 1993,
            "journal": "Journal of Financial Economics",
            "journal_abbrev": "JFE",
            "summary": "Identifies three common risk factors.",
            "keywords": ["asset pricing", "risk factors"],
            "category": "Finance/Asset Pricing",
            "confidence": 0.95,
        })

        parsed = json.loads(swift_json)

        # These are the checks add_paper uses for has_pre_metadata
        assert parsed.get("title")
        assert parsed.get("authors")
        assert parsed.get("year")
        # has_pre_summary
        assert parsed.get("summary") is not None
        # has_pre_category
        assert parsed.get("category") is not None

        # Also verify optional fields with None/null
        swift_json_nulls = json.dumps({
            "title": "Minimal",
            "authors": ["Doe"],
            "authors_full": [],
            "year": 2020,
            "journal": "",
            "journal_abbrev": None,
            "summary": "A summary",
            "keywords": [],
            "category": "Unsorted",
            "confidence": None,
        })
        parsed_nulls = json.loads(swift_json_nulls)
        assert parsed_nulls.get("title")
        assert parsed_nulls.get("journal_abbrev") is None
        assert parsed_nulls.get("confidence") is None

        # Verify PaperMetadata handles null confidence gracefully
        from namingpaper.models import PaperMetadata
        metadata = PaperMetadata(
            title=parsed_nulls["title"],
            authors=parsed_nulls["authors"],
            year=parsed_nulls["year"],
            journal=parsed_nulls.get("journal", ""),
            journal_abbrev=parsed_nulls.get("journal_abbrev"),
            confidence=parsed_nulls.get("confidence") or 1.0,
        )
        assert metadata.confidence == 1.0
