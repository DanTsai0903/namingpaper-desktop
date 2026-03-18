"""Tests for the categorizer module."""

from pathlib import Path

import pytest

from namingpaper.categorizer import (
    discover_categories,
    _parse_category_json,
    prompt_category_selection,
)


class TestDiscoverCategories:
    def test_discovers_leaf_folders(self, tmp_path):
        (tmp_path / "Finance" / "Asset Pricing").mkdir(parents=True)
        (tmp_path / "Finance" / "Empirical").mkdir(parents=True)
        (tmp_path / "Machine Learning" / "NLP").mkdir(parents=True)
        categories = discover_categories(tmp_path)
        assert "Finance" not in categories
        assert "Finance/Asset Pricing" in categories
        assert "Finance/Empirical" in categories
        assert "Machine Learning" not in categories
        assert "Machine Learning/NLP" in categories

    def test_keeps_parent_when_it_contains_pdfs(self, tmp_path):
        (tmp_path / "Finance" / "Asset Pricing").mkdir(parents=True)
        (tmp_path / "Finance" / "overview.pdf").write_bytes(b"%PDF-1.4")

        categories = discover_categories(tmp_path)

        assert "Finance" in categories
        assert "Finance/Asset Pricing" in categories

    def test_excludes_unsorted(self, tmp_path):
        (tmp_path / "Unsorted").mkdir()
        (tmp_path / "Finance").mkdir()
        categories = discover_categories(tmp_path)
        assert "Unsorted" not in categories
        assert "Finance" in categories

    def test_empty_directory(self, tmp_path):
        categories = discover_categories(tmp_path)
        assert categories == []

    def test_nonexistent_directory(self):
        categories = discover_categories(Path("/nonexistent/path"))
        assert categories == []


class TestParseCategoryJson:
    def test_valid_json(self):
        result = _parse_category_json('{"category": "Finance/Asset Pricing"}')
        assert result == "Finance/Asset Pricing"

    def test_json_in_code_block(self):
        result = _parse_category_json('```json\n{"category": "Economics"}\n```')
        assert result == "Economics"

    def test_invalid_json(self):
        result = _parse_category_json("not json")
        assert result == "Unsorted"

    def test_missing_category_field(self):
        result = _parse_category_json('{"other": "value"}')
        assert result == "Unsorted"


class TestPromptCategorySelection:
    def test_auto_yes(self):
        result = prompt_category_selection(
            suggested="Finance/Asset Pricing",
            existing_categories=["Finance/Asset Pricing", "Economics"],
            auto_yes=True,
        )
        assert result == "Finance/Asset Pricing"
