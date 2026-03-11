"""AI-powered paper summarization and keyword extraction."""

import json
import re

from namingpaper.models import PDFContent
from namingpaper.providers.base import AIProvider

_RE_JSON_BLOCK = re.compile(r"```json\s*(.*?)```", re.DOTALL)
_RE_CODE_BLOCK = re.compile(r"```\s*(.*?)```", re.DOTALL)

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


def _parse_summary_json(response_text: str) -> tuple[str | None, list[str]]:
    """Parse AI response to extract summary and keywords.

    Handles markdown code blocks and partial results.
    """
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
        return None, []

    summary = data.get("summary")
    keywords = data.get("keywords", [])
    if isinstance(keywords, list):
        keywords = [str(k).lower() for k in keywords]
    else:
        keywords = []

    return summary, keywords
