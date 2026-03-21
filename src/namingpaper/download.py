"""Download papers from the library to an output directory."""

import shutil
from dataclasses import dataclass, field
from pathlib import Path

from namingpaper.models import Paper


@dataclass
class DownloadSummary:
    """Summary of a download operation."""

    total: int = 0
    copied: int = 0
    skipped: int = 0
    failed: int = 0
    failed_papers: list[str] = field(default_factory=list)


def download_papers(
    papers: list[Paper],
    output_dir: Path,
    *,
    flat: bool = False,
    overwrite: bool = False,
) -> DownloadSummary:
    """Copy papers from the library to an output directory.

    Args:
        papers: Papers to download.
        output_dir: Destination directory.
        flat: If True, place all PDFs in root of output_dir (no category subfolders).
        overwrite: If True, replace existing files. Otherwise skip them.

    Returns:
        A DownloadSummary with counts for copied, skipped, and failed papers.
    """
    summary = DownloadSummary(total=len(papers))
    seen_names: dict[str, str] = {}  # filename -> paper_id (for flat collision detection)

    for paper in papers:
        source = Path(paper.file_path)

        if not source.exists():
            summary.failed += 1
            summary.failed_papers.append(paper.id)
            continue

        target = _resolve_target(paper, output_dir, flat, seen_names)

        if target.exists() and not overwrite:
            summary.skipped += 1
            continue

        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        summary.copied += 1

    return summary


def resolve_target_path(
    paper: Paper,
    output_dir: Path,
    flat: bool = False,
) -> Path:
    """Resolve the target path for a paper (for dry-run display).

    This is a simplified version that doesn't track flat-mode collisions
    across multiple calls, suitable for preview output.
    """
    filename = Path(paper.file_path).name
    if flat:
        return output_dir / filename
    category = paper.category or "Unsorted"
    return output_dir / category / filename


def _resolve_target(
    paper: Paper,
    output_dir: Path,
    flat: bool,
    seen_names: dict[str, str],
) -> Path:
    """Resolve the target path, handling flat-mode filename collisions."""
    filename = Path(paper.file_path).name

    if flat:
        if filename in seen_names and seen_names[filename] != paper.id:
            # Collision: append paper ID before extension
            stem = Path(filename).stem
            suffix = Path(filename).suffix
            filename = f"{stem}_{paper.id}{suffix}"
        seen_names[filename] = paper.id
        return output_dir / filename

    category = paper.category or "Unsorted"
    return output_dir / category / filename
