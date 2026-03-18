"""AI-powered paper categorization."""

import json
import re
from pathlib import Path

from rich.console import Console
from rich.prompt import IntPrompt, Prompt

from namingpaper.providers.base import AIProvider

_RE_JSON_BLOCK = re.compile(r"```json\s*(.*?)```", re.DOTALL)
_RE_CODE_BLOCK = re.compile(r"```\s*(.*?)```", re.DOTALL)

CATEGORIZATION_PROMPT = """Given a paper with the following summary and keywords, suggest the best category folder.

Summary: {summary}
Keywords: {keywords}

Existing categories (for reference only):
{categories}

Return ONLY valid JSON with:
- category: string (the most accurate and descriptive category for this paper)

Use "/" for nested categories (e.g., "Finance/Asset Pricing").
You may use an existing category if it fits well, but DO NOT default to existing categories.
If you can think of a more specific, accurate, or descriptive category name, use that instead.
The goal is the best possible organization, not matching existing folders.

Only return valid JSON, no other text."""


def discover_categories(papers_dir: Path) -> list[str]:
    """Scan papers_dir subdirectories to find existing categories.

    Returns category paths relative to papers_dir (e.g., "Finance/Asset Pricing").
    Excludes the "Unsorted" directory and skips intermediate folders that only
    exist to group more specific categories.
    """
    categories: list[str] = []
    if not papers_dir.is_dir():
        return categories

    for path in sorted(papers_dir.rglob("*")):
        if not path.is_dir():
            continue
        rel = path.relative_to(papers_dir)
        name = str(rel)
        if name == "Unsorted" or name.startswith("Unsorted/"):
            continue
        try:
            children = list(path.iterdir())
        except OSError:
            continue

        has_pdf = any(
            child.is_file() and child.suffix.lower() == ".pdf" for child in children
        )
        has_child_dir = any(child.is_dir() for child in children)

        # Only include leaf directories or directories that directly contain PDFs.
        if has_pdf or not has_child_dir:
            categories.append(name)

    return categories


async def suggest_category(
    summary: str | None,
    keywords: list[str],
    existing_categories: list[str],
    provider: AIProvider,
) -> str:
    """Use AI to suggest the best category for a paper.

    Returns a category path string.
    """
    if not summary and not keywords:
        return "Unsorted"

    cats_text = "\n".join(f"- {c}" for c in existing_categories) if existing_categories else "(none yet)"
    prompt = CATEGORIZATION_PROMPT.format(
        summary=summary or "(no summary)",
        keywords=", ".join(keywords) if keywords else "(none)",
        categories=cats_text,
    )

    response_text = await provider.call_raw(prompt)
    return _parse_category_json(response_text)


def _parse_category_json(response_text: str) -> str:
    """Parse AI response to extract category suggestion."""
    json_text = response_text
    match = _RE_JSON_BLOCK.search(response_text)
    if match:
        json_text = match.group(1)
    else:
        match = _RE_CODE_BLOCK.search(response_text)
        if match:
            json_text = match.group(1)

    try:
        data = json.loads(json_text.strip())
    except json.JSONDecodeError:
        return "Unsorted"

    return data.get("category", "Unsorted")


def prompt_category_selection(
    suggested: str,
    existing_categories: list[str],
    auto_yes: bool = False,
    console: Console | None = None,
) -> str:
    """Interactive category selection prompt.

    Args:
        suggested: AI-suggested category
        existing_categories: List of existing category paths
        auto_yes: If True, auto-accept the AI suggestion
        console: Rich console for output

    Returns:
        Selected category path string.
    """
    if auto_yes:
        return suggested

    c = console or Console()

    # Build options list
    options: list[str] = []
    suggested_idx = None

    # AI suggestion first (if it's in the existing list, don't duplicate)
    if suggested not in existing_categories and suggested != "Unsorted":
        options.append(suggested)
        suggested_idx = 0

    for cat in existing_categories:
        if cat == suggested:
            suggested_idx = len(options)
        options.append(cat)

    c.print()
    c.print("[bold]Available categories:[/bold]")
    for i, opt in enumerate(options, 1):
        marker = " [cyan]<-- AI suggestion[/cyan]" if i - 1 == suggested_idx else ""
        c.print(f"  {i}. {opt}{marker}")

    create_idx = len(options) + 1
    skip_idx = len(options) + 2
    c.print(f"  {create_idx}. [dim]\\[Create new category][/dim]")
    c.print(f"  {skip_idx}. [dim]\\[Skip -- leave in Unsorted/][/dim]")

    default = (suggested_idx or 0) + 1
    choice = IntPrompt.ask(
        f"\nYour choice", default=default, console=c
    )

    if choice == skip_idx:
        return "Unsorted"
    if choice == create_idx:
        new_cat = Prompt.ask("Category path (e.g., Finance/Asset Pricing)", console=c)
        return new_cat.strip() or "Unsorted"
    if 1 <= choice <= len(options):
        return options[choice - 1]

    return suggested
