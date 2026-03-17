"""AI-powered paper summarization and keyword extraction."""

import json
import re

from pydantic import ValidationError

from namingpaper.config import get_settings
from namingpaper.models import PDFContent, PaperMetadata
from namingpaper.providers.base import AIProvider

_RE_JSON_BLOCK = re.compile(r"```json\s*(.*?)```", re.DOTALL)
_RE_CODE_BLOCK = re.compile(r"```\s*(.*?)```", re.DOTALL)
_RE_JSON_OBJECT = re.compile(r"\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}", re.DOTALL)

SUMMARIZATION_PROMPT = """Read this academic paper and provide:
1. A concise summary (2-4 sentences) describing the paper's main contribution
2. A list of 3-8 descriptive keywords or key phrases (lowercase, domain-relevant)

Return ONLY valid JSON with these fields:
- summary: string (2-4 sentences)
- keywords: list of lowercase strings (3-8 items)

Example:
{
  "summary": "This paper identifies three common risk factors in stock returns...",
  "keywords": ["asset pricing", "risk factors", "size effect", "value effect"]
}

Only return valid JSON, no other text."""

ANALYSIS_PROMPT = """Read this academic paper and provide:
1. Metadata:
   - authors: list of author last names only (e.g., ["Fama", "French"])
   - authors_full: list of author full names (e.g., ["Eugene F. Fama", "Kenneth R. French"])
   - year: publication year as integer
   - journal: full journal name
   - journal_abbrev: common abbreviation if known, otherwise null
   - title: paper title (main title only)
   - confidence: your confidence from 0.0 to 1.0
2. A concise summary (2-4 sentences) describing the paper's main contribution
3. A list of 3-8 descriptive keywords or key phrases (lowercase, domain-relevant)

If this document is NOT an academic paper, still return valid JSON but set confidence to 0.0, summary to null, and keywords to [].

Return ONLY valid JSON with these fields:
- authors
- authors_full
- year
- journal
- journal_abbrev
- title
- confidence
- summary
- keywords

Common journal abbreviations:
- Journal of Finance -> JF
- Journal of Financial Economics -> JFE
- Review of Financial Studies -> RFS
- American Economic Review -> AER
- Quarterly Journal of Economics -> QJE
- Journal of Political Economy -> JPE
- Econometrica -> ECMA
- Review of Economic Studies -> REStud
- Journal of Monetary Economics -> JME
- Journal of Economic Theory -> JET

Only return valid JSON, no other text."""


class PaperAnalysisParseError(RuntimeError):
    """Raised when combined paper analysis JSON cannot be parsed safely."""


async def analyze_paper(
    content: PDFContent,
    provider: AIProvider,
) -> tuple[PaperMetadata, str | None, list[str]]:
    """Extract metadata, summary, and keywords in a single text-model request."""
    settings = get_settings()
    text = provider._truncate_text(content.text, settings.max_text_chars)
    prompt = f"{ANALYSIS_PROMPT}\n\nPaper text:\n{text}"
    response_text = await provider.call_raw(prompt)
    return _parse_analysis_json(response_text)


async def summarize_paper(
    content: PDFContent,
    provider: AIProvider,
) -> tuple[str | None, list[str]]:
    """Generate summary and keywords for a paper.

    Args:
        content: PDF content (text and optional image)
        provider: AI provider to use for summarization

    Returns:
        Tuple of (summary, keywords). Summary may be None on failure.
    """
    text = provider._truncate_text(content.text, 6000)
    prompt = f"{SUMMARIZATION_PROMPT}\n\nPaper text:\n{text}"
    response_text = await provider.call_raw(prompt)
    return _parse_summary_json(response_text)


def _extract_json_data(response_text: str) -> dict | None:
    """Extract a JSON object from a model response."""
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
        match = _RE_JSON_OBJECT.search(response_text)
        if not match:
            return None
        try:
            data = json.loads(match.group())
        except json.JSONDecodeError:
            return None

    return data if isinstance(data, dict) else None


def _normalize_keywords(raw_keywords: object) -> list[str]:
    """Normalize model-provided keywords into lowercase strings."""
    if not isinstance(raw_keywords, list):
        return []
    return [str(keyword).lower() for keyword in raw_keywords]


def _parse_summary_json(response_text: str) -> tuple[str | None, list[str]]:
    """Parse AI response to extract summary and keywords.

    Handles markdown code blocks and partial results.
    """
    data = _extract_json_data(response_text)
    if data is None:
        return None, []

    summary = data.get("summary")
    if summary is not None and not isinstance(summary, str):
        summary = str(summary)
    keywords = _normalize_keywords(data.get("keywords", []))

    return summary, keywords


def _parse_analysis_json(
    response_text: str,
) -> tuple[PaperMetadata, str | None, list[str]]:
    """Parse combined metadata + summary JSON from a model response."""
    data = _extract_json_data(response_text)
    if data is None:
        raise PaperAnalysisParseError("Failed to parse paper analysis JSON.")

    try:
        metadata = PaperMetadata(
            authors=data.get("authors", []),
            authors_full=data.get("authors_full", []),
            year=data.get("year"),
            journal=data.get("journal", ""),
            journal_abbrev=data.get("journal_abbrev"),
            title=data.get("title"),
            confidence=data.get("confidence", 1.0),
        )
    except ValidationError as e:
        raise PaperAnalysisParseError(
            f"Paper analysis returned malformed metadata: {e}"
        ) from e

    summary = data.get("summary")
    if summary is not None and not isinstance(summary, str):
        summary = str(summary)
    keywords = _normalize_keywords(data.get("keywords", []))

    return metadata, summary, keywords
