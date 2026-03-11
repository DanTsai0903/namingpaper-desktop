"""High-level library operations — add, search, sync, remove."""

import shutil
from datetime import datetime, timezone
from pathlib import Path

from namingpaper.categorizer import (
    discover_categories,
    prompt_category_selection,
    suggest_category,
)
from namingpaper.config import get_settings
from namingpaper.database import Database, compute_file_hash, generate_paper_id
from namingpaper.extractor import extract_metadata
from namingpaper.formatter import build_filename
from namingpaper.models import Paper, PaperMetadata, SearchFilter
from namingpaper.pdf_reader import extract_pdf_content
from namingpaper.providers import get_provider
from namingpaper.providers.base import AIProvider
from namingpaper.summarizer import summarize_paper


class AddResult:
    """Result of adding a paper to the library."""

    def __init__(
        self,
        paper: Paper | None = None,
        skipped: bool = False,
        error: str | None = None,
        existing: Paper | None = None,
    ):
        self.paper = paper
        self.skipped = skipped
        self.error = error
        self.existing = existing


async def add_paper(
    pdf_path: Path,
    db: Database,
    provider: AIProvider | None = None,
    provider_name: str | None = None,
    model_name: str | None = None,
    ocr_model: str | None = None,
    template: str | None = None,
    copy: bool = False,
    auto_yes: bool = False,
    execute: bool = False,
) -> AddResult:
    """Add a paper to the library: extract → rename → summarize → categorize → file → persist.

    Args:
        pdf_path: Path to the PDF file
        db: Open database connection
        provider: Pre-initialized AI provider
        provider_name: Provider name if provider not given
        model_name: Override model
        ocr_model: Override OCR model
        template: Filename template
        copy: If True, copy instead of move
        auto_yes: Auto-accept AI suggestions
        execute: If True, perform mutations

    Returns:
        AddResult with the paper record or error info
    """
    settings = get_settings()
    papers_dir = settings.papers_dir

    # 1. Compute hash and check for duplicates
    sha256 = compute_file_hash(pdf_path)
    existing = db.get_paper_by_hash(sha256)
    if existing:
        return AddResult(skipped=True, existing=existing)

    # 2. Get or create provider
    created_provider = False
    if provider is None:
        provider = get_provider(provider_name, model_name=model_name, ocr_model=ocr_model)
        created_provider = True

    try:
        # 3. Extract metadata (reuses existing pipeline)
        metadata = await extract_metadata(
            pdf_path, provider=provider, model_name=model_name, ocr_model=ocr_model
        )

        # 4. Build filename
        if template:
            from namingpaper.template import build_filename_from_template
            filename = build_filename_from_template(metadata, template)
        else:
            filename = build_filename(metadata)

        # 5. Summarize
        content = extract_pdf_content(pdf_path)
        summary, keywords = await summarize_paper(content, provider)

        # 6. Categorize
        categories = discover_categories(papers_dir)
        suggested = await suggest_category(summary, keywords, categories, provider)
        category = prompt_category_selection(
            suggested, categories, auto_yes=auto_yes
        )

        # 7. Determine destination
        dest_dir = papers_dir / category
        dest_path = dest_dir / filename

        if not execute:
            # Dry-run: return what would happen
            now = datetime.now(timezone.utc).isoformat()
            paper = Paper(
                id=generate_paper_id(sha256),
                sha256=sha256,
                title=metadata.title,
                authors=metadata.authors,
                authors_full=metadata.authors_full,
                year=metadata.year,
                journal=metadata.journal,
                journal_abbrev=metadata.journal_abbrev,
                summary=summary,
                keywords=keywords,
                category=category,
                file_path=str(dest_path),
                confidence=metadata.confidence,
                created_at=now,
                updated_at=now,
            )
            return AddResult(paper=paper)

        # 8. Execute: create dirs, move/copy file
        dest_dir.mkdir(parents=True, exist_ok=True)
        if copy:
            shutil.copy2(pdf_path, dest_path)
        else:
            shutil.move(str(pdf_path), str(dest_path))

        # 9. Persist to database
        now = datetime.now(timezone.utc).isoformat()
        paper = Paper(
            id=generate_paper_id(sha256),
            sha256=sha256,
            title=metadata.title,
            authors=metadata.authors,
            authors_full=metadata.authors_full,
            year=metadata.year,
            journal=metadata.journal,
            journal_abbrev=metadata.journal_abbrev,
            summary=summary,
            keywords=keywords,
            category=category,
            file_path=str(dest_path),
            confidence=metadata.confidence,
            created_at=now,
            updated_at=now,
        )
        db.create_paper(paper)
        return AddResult(paper=paper)

    finally:
        if created_provider and hasattr(provider, "aclose"):
            await provider.aclose()


async def import_directory(
    directory: Path,
    db: Database,
    provider_name: str | None = None,
    model_name: str | None = None,
    ocr_model: str | None = None,
    template: str | None = None,
    copy: bool = False,
    auto_yes: bool = False,
    execute: bool = False,
    recursive: bool = False,
    parallel: int = 1,
    progress_callback: object = None,
) -> list[AddResult]:
    """Import all PDFs from a directory into the library."""
    import asyncio

    if recursive:
        pdf_files = sorted(directory.rglob("*.pdf"))
    else:
        pdf_files = sorted(directory.glob("*.pdf"))

    if not pdf_files:
        return []

    provider = get_provider(provider_name, model_name=model_name, ocr_model=ocr_model)
    results: list[AddResult] = [AddResult() for _ in pdf_files]
    completed = 0

    async def _process(idx: int, pdf_path: Path, sem: asyncio.Semaphore) -> None:
        nonlocal completed
        async with sem:
            try:
                result = await add_paper(
                    pdf_path,
                    db=db,
                    provider=provider,
                    template=template,
                    copy=copy,
                    auto_yes=auto_yes,
                    execute=execute,
                )
                results[idx] = result
            except Exception as e:
                results[idx] = AddResult(error=str(e))
            completed += 1
            if callable(progress_callback):
                progress_callback(completed, len(pdf_files))

    try:
        if parallel <= 1:
            for i, pdf_path in enumerate(pdf_files):
                await _process(i, pdf_path, asyncio.Semaphore(1))
        else:
            sem = asyncio.Semaphore(parallel)
            tasks = [_process(i, p, sem) for i, p in enumerate(pdf_files)]
            await asyncio.gather(*tasks)
    finally:
        if hasattr(provider, "aclose"):
            await provider.aclose()

    return results


def sync_library(
    db: Database,
    papers_dir: Path | None = None,
) -> tuple[list[Path], list[Paper]]:
    """Reconcile database with filesystem.

    Returns:
        (untracked_files, missing_records)
        - untracked_files: PDFs in papers_dir not in database
        - missing_records: DB records whose files no longer exist
    """
    if papers_dir is None:
        papers_dir = get_settings().papers_dir

    # Find all PDFs on disk
    disk_files = set(papers_dir.rglob("*.pdf"))
    disk_paths = {str(p) for p in disk_files}

    # Get all records from DB
    all_papers = db.list_papers(limit=100000)
    db_paths = {p.file_path for p in all_papers}

    # Untracked: on disk but not in DB
    untracked = sorted(p for p in disk_files if str(p) not in db_paths)

    # Missing: in DB but not on disk
    missing = [p for p in all_papers if p.file_path not in disk_paths]

    return untracked, missing


def remove_paper(
    db: Database,
    paper_id: str,
    delete_file: bool = False,
) -> Paper | None:
    """Remove a paper from the library.

    Returns the paper record if found, None otherwise.
    """
    paper = db.get_paper(paper_id)
    if paper is None:
        return None

    if delete_file:
        file_path = Path(paper.file_path)
        if file_path.exists():
            file_path.unlink()

    db.delete_paper(paper_id)
    return paper


def search_library(
    db: Database,
    query: str | None = None,
    filters: SearchFilter | None = None,
) -> list[Paper]:
    """Search the library using FTS and/or filters."""
    return db.search(query=query, filters=filters)


async def smart_search(
    db: Database,
    query: str,
    provider: AIProvider | None = None,
    provider_name: str | None = None,
    model_name: str | None = None,
) -> list[Paper]:
    """Semantic search: AI ranks papers by relevance to the query."""
    # Get all papers with summaries
    all_papers = db.list_papers(limit=1000)
    papers_with_summaries = [p for p in all_papers if p.summary]

    if not papers_with_summaries:
        return []

    created_provider = False
    if provider is None:
        provider = get_provider(provider_name, model_name=model_name)
        created_provider = True

    try:
        # Build context for AI
        papers_text = "\n".join(
            f"ID:{p.id} | {p.title} | Summary: {p.summary}"
            for p in papers_with_summaries
        )

        prompt = (
            f"Given this search query: \"{query}\"\n\n"
            f"Rank these papers by relevance. Return ONLY a JSON list of paper IDs "
            f"ordered from most to least relevant. Only include relevant papers.\n\n"
            f"Papers:\n{papers_text}\n\n"
            f"Return JSON: {{\"ids\": [\"id1\", \"id2\", ...]}}"
        )

        response = await provider.call_raw(prompt)

        import json, re
        json_match = re.search(r"\{.*\}", response, re.DOTALL)
        if json_match:
            data = json.loads(json_match.group())
            ranked_ids = data.get("ids", [])
        else:
            ranked_ids = []

        # Return papers in ranked order
        paper_map = {p.id: p for p in papers_with_summaries}
        return [paper_map[pid] for pid in ranked_ids if pid in paper_map]

    finally:
        if created_provider and hasattr(provider, "aclose"):
            await provider.aclose()
