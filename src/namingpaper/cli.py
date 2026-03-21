"""CLI entry point for namingpaper."""

from pathlib import Path
import shutil
import subprocess
import sys
from typing import Annotated

import typer
from rich.console import Console
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TaskProgressColumn
from rich.table import Table

from namingpaper import __version__
from namingpaper.config import get_settings
from namingpaper.extractor import plan_rename_sync
from namingpaper.models import BatchItem, BatchItemStatus, LowConfidenceError
from namingpaper.renamer import (
    CollisionStrategy,
    execute_rename,
    preview_rename,
    check_collision,
)

app = typer.Typer(
    name="namingpaper",
    help="Rename academic papers using AI-extracted metadata.",
    no_args_is_help=True,
)
console = Console()


def _show_version(value: bool) -> None:
    """Print version and exit when --version/-v is provided."""
    if value:
        console.print(f"namingpaper {__version__}")
        raise typer.Exit()


@app.callback()
def main(
    version: Annotated[
        bool,
        typer.Option(
            "--version",
            "-v",
            callback=_show_version,
            is_eager=True,
            help="Show namingpaper version and exit",
        ),
    ] = False,
) -> None:
    """namingpaper CLI."""


@app.command()
def version() -> None:
    """Show namingpaper version."""
    console.print(f"namingpaper {__version__}")


@app.command()
def rename(
    pdf_path: Annotated[
        Path,
        typer.Argument(
            help="Path to the PDF file to rename",
            exists=True,
            dir_okay=False,
            resolve_path=True,
        ),
    ],
    execute: Annotated[
        bool,
        typer.Option(
            "--execute",
            "-x",
            help="Actually rename the file (default is dry-run)",
        ),
    ] = False,
    yes: Annotated[
        bool,
        typer.Option(
            "--yes",
            "-y",
            help="Skip confirmation prompt",
        ),
    ] = False,
    provider: Annotated[
        str | None,
        typer.Option(
            "--provider",
            "-p",
            help="AI provider to use (claude, openai, gemini, ollama, omlx)",
        ),
    ] = None,
    model: Annotated[
        str | None,
        typer.Option(
            "--model",
            "-m",
            help="Override the default model for the provider",
        ),
    ] = None,
    ocr_model: Annotated[
        str | None,
        typer.Option(
            "--ocr-model",
            help="Override Ollama OCR model (default: deepseek-ocr)",
        ),
    ] = None,
    output_dir: Annotated[
        Path | None,
        typer.Option(
            "--output-dir",
            "-o",
            help="Copy renamed file to this directory (keeps original)",
            exists=True,
            file_okay=False,
            resolve_path=True,
        ),
    ] = None,
    template: Annotated[
        str | None,
        typer.Option(
            "--template",
            "-t",
            help="Filename template or preset (default, compact, full, simple)",
        ),
    ] = None,
    collision: Annotated[
        CollisionStrategy,
        typer.Option(
            "--collision",
            "-c",
            help="How to handle filename collisions",
        ),
    ] = CollisionStrategy.SKIP,
    reasoning: Annotated[
        bool | None,
        typer.Option("--reasoning/--no-reasoning", help="Enable/disable reasoning mode"),
    ] = None,
) -> None:
    """Rename a PDF file based on AI-extracted metadata.

    By default, runs in dry-run mode showing what would happen.
    Use --execute to actually rename the file.
    """
    # Check file extension
    if pdf_path.suffix.lower() != ".pdf":
        console.print(f"[red]Error:[/red] File must be a PDF: {pdf_path}")
        raise typer.Exit(1)

    # Resolve template: CLI flag > config/env > default
    settings = get_settings()
    if template is None:
        template = settings.template

    # Validate template
    from namingpaper.template import validate_template, get_template
    template_str = get_template(template)
    is_valid, error = validate_template(template_str)
    if not is_valid:
        console.print(f"[red]Invalid template:[/red] {error}")
        raise typer.Exit(1)

    # Extract metadata and plan rename
    with console.status("[bold blue]Extracting metadata..."):
        try:
            operation = plan_rename_sync(pdf_path, provider_name=provider, model_name=model, ocr_model=ocr_model, keep_alive="0s", reasoning=reasoning)
        except LowConfidenceError as e:
            console.print(
                f"[yellow]Skipped:[/yellow] {e}"
            )
            raise typer.Exit(2)
        except ValueError as e:
            console.print(f"[red]Error:[/red] {e}")
            raise typer.Exit(1)
        except Exception as e:
            console.print(f"[red]Error extracting metadata:[/red] {e}")
            raise typer.Exit(1)

    # Apply template
    from namingpaper.template import build_filename_from_template
    filename = build_filename_from_template(operation.metadata, template)
    operation.destination = pdf_path.parent / filename

    # If output_dir specified, update destination to that directory
    copy_mode = output_dir is not None
    if output_dir:
        operation.destination = output_dir / operation.destination.name

    # Display metadata
    metadata = operation.metadata
    table = Table(title="Extracted Metadata", show_header=False)
    table.add_column("Field", style="cyan")
    table.add_column("Value")

    table.add_row("Authors", ", ".join(metadata.authors))
    table.add_row("Year", str(metadata.year))
    table.add_row("Journal", metadata.journal)
    if metadata.journal_abbrev:
        table.add_row("Abbreviation", metadata.journal_abbrev)
    table.add_row("Title", metadata.title)
    table.add_row("Confidence", f"{metadata.confidence:.0%}")

    console.print(table)
    console.print()

    # Show planned rename
    preview = preview_rename(operation, copy=copy_mode)
    title = "Planned Copy" if copy_mode else "Planned Rename"
    console.print(Panel(preview, title=title, border_style="blue"))

    # Check for collision
    if check_collision(operation.destination):
        console.print(
            f"[yellow]Warning:[/yellow] Destination exists. "
            f"Strategy: [bold]{collision.value}[/bold]"
        )

    # Dry run mode
    if not execute:
        console.print()
        action = "copy" if copy_mode else "rename"
        console.print(f"[dim]Dry run mode. Use --execute to {action}.[/dim]")
        return

    # Confirm
    if not yes:
        action = "copy" if copy_mode else "rename"
        confirmed = typer.confirm(f"Proceed with {action}?")
        if not confirmed:
            console.print("[yellow]Cancelled.[/yellow]")
            raise typer.Exit(0)

    # Execute rename/copy
    result = execute_rename(operation, collision_strategy=collision, copy=copy_mode)

    if result is None:
        console.print("[yellow]Skipped:[/yellow] File already exists.")
    elif copy_mode:
        console.print(f"[green]Copied to:[/green] {result}")
    else:
        console.print(f"[green]Renamed to:[/green] {result}")


@app.command()
def batch(
    directory: Annotated[
        Path,
        typer.Argument(
            help="Directory containing PDF files to process",
            exists=True,
            file_okay=False,
            resolve_path=True,
        ),
    ],
    execute: Annotated[
        bool,
        typer.Option(
            "--execute",
            "-x",
            help="Actually rename files (default is dry-run)",
        ),
    ] = False,
    yes: Annotated[
        bool,
        typer.Option(
            "--yes",
            "-y",
            help="Skip confirmation prompt",
        ),
    ] = False,
    recursive: Annotated[
        bool,
        typer.Option(
            "--recursive",
            "-r",
            help="Scan subdirectories for PDF files",
        ),
    ] = False,
    filter_pattern: Annotated[
        str | None,
        typer.Option(
            "--filter",
            "-f",
            help="Only process files matching this pattern (e.g., '2023*')",
        ),
    ] = None,
    provider: Annotated[
        str | None,
        typer.Option(
            "--provider",
            "-p",
            help="AI provider to use (claude, openai, gemini, ollama, omlx)",
        ),
    ] = None,
    model: Annotated[
        str | None,
        typer.Option(
            "--model",
            "-m",
            help="Override the default model for the provider",
        ),
    ] = None,
    ocr_model: Annotated[
        str | None,
        typer.Option(
            "--ocr-model",
            help="Override Ollama OCR model (default: deepseek-ocr)",
        ),
    ] = None,
    template: Annotated[
        str | None,
        typer.Option(
            "--template",
            "-t",
            help="Filename template or preset (default, compact, full, simple)",
        ),
    ] = None,
    output_dir: Annotated[
        Path | None,
        typer.Option(
            "--output-dir",
            "-o",
            help="Copy renamed files to this directory (keeps originals)",
            exists=True,
            file_okay=False,
            resolve_path=True,
        ),
    ] = None,
    collision: Annotated[
        CollisionStrategy,
        typer.Option(
            "--collision",
            "-c",
            help="How to handle filename collisions",
        ),
    ] = CollisionStrategy.SKIP,
    parallel: Annotated[
        int,
        typer.Option(
            "--parallel",
            help="Concurrent extractions (0 = auto: 4 for oMLX, 1 for others)",
        ),
    ] = 0,
    json_output: Annotated[
        bool,
        typer.Option(
            "--json",
            help="Output results as JSON",
        ),
    ] = False,
) -> None:
    """Batch rename PDF files in a directory.

    By default, runs in dry-run mode showing what would happen.
    Use --execute to actually rename files.

    Template placeholders:
      {authors}        - Author surnames
      {authors_full}   - Author full names
      {authors_abbrev} - Surname with initials
      {year}           - Publication year
      {journal}        - Journal abbreviation
      {journal_full}   - Full journal name
      {title}          - Paper title

    Preset templates: default, compact, full, simple
    """
    from namingpaper.batch import (
        scan_directory,
        process_batch_sync,
        detect_batch_collisions,
        execute_batch,
    )
    from namingpaper.template import validate_template, get_template
    import json

    # Resolve template: CLI flag > config/env > default
    settings = get_settings()
    if template is None:
        template = settings.template

    # Validate template
    template_str = get_template(template)
    is_valid, error = validate_template(template_str)
    if not is_valid:
        console.print(f"[red]Invalid template:[/red] {error}")
        raise typer.Exit(1)

    # Scan directory
    console.print(f"[blue]Scanning[/blue] {directory}...")
    pdf_files = scan_directory(directory, recursive=recursive, pattern=filter_pattern)

    if not pdf_files:
        console.print("[yellow]No PDF files found.[/yellow]")
        raise typer.Exit(0)

    console.print(f"Found [bold]{len(pdf_files)}[/bold] PDF file(s)")
    console.print()

    # Process files with progress bar
    items: list[BatchItem] = []

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        TaskProgressColumn(),
        console=console,
    ) as progress:
        task = progress.add_task("Extracting metadata...", total=len(pdf_files))

        def on_progress(current: int, total: int, item: BatchItem) -> None:
            progress.update(task, completed=current, description=f"Processing: {item.source.name[:40]}")

        try:
            items = process_batch_sync(
                pdf_files,
                provider_name=provider,
                model_name=model,
                ocr_model=ocr_model,
                template=template,
                output_dir=output_dir,
                parallel=parallel,
                progress_callback=on_progress,
            )
        except Exception as e:
            console.print(f"[red]Error during extraction:[/red] {e}")
            raise typer.Exit(1)

    # Detect internal collisions
    items = detect_batch_collisions(items)

    # Compute status counts once
    ok_count = sum(1 for i in items if i.status == BatchItemStatus.OK)
    collision_count = sum(1 for i in items if i.status == BatchItemStatus.COLLISION)
    error_count = sum(1 for i in items if i.status == BatchItemStatus.ERROR)
    skipped_count = sum(1 for i in items if i.status == BatchItemStatus.SKIPPED)

    # JSON output mode
    if json_output:
        output = {
            "files": [
                {
                    "source": str(item.source),
                    "destination": str(item.destination) if item.destination else None,
                    "status": item.status.value,
                    "error": item.error,
                    "metadata": item.metadata.model_dump() if item.metadata else None,
                }
                for item in items
            ],
            "summary": {
                "total": len(items),
                "ok": ok_count,
                "collision": collision_count,
                "error": error_count,
                "skipped": skipped_count,
            },
        }
        print(json.dumps(output, indent=2))
        return

    # Display preview table
    console.print()
    table = Table(title="Planned Renames", show_lines=True)
    table.add_column("#", style="dim", width=4)
    table.add_column("Original", style="cyan", max_width=40)
    table.add_column("New Name", max_width=50)
    table.add_column("Status", width=10)
    table.add_column("Confidence", width=10)

    status_styles = {
        BatchItemStatus.OK: "[green]OK[/green]",
        BatchItemStatus.COLLISION: "[yellow]COLLISION[/yellow]",
        BatchItemStatus.ERROR: "[red]ERROR[/red]",
        BatchItemStatus.PENDING: "[dim]PENDING[/dim]",
        BatchItemStatus.SKIPPED: "[dim]SKIPPED[/dim]",
        BatchItemStatus.COMPLETED: "[green]DONE[/green]",
    }

    for i, item in enumerate(items, 1):
        status_str = status_styles.get(item.status, str(item.status))
        confidence = f"{item.metadata.confidence:.0%}" if item.metadata else "-"
        new_name = item.destination.name if item.destination else item.error or "N/A"

        if item.status == BatchItemStatus.ERROR:
            new_name = f"[red]{item.error}[/red]"

        table.add_row(
            str(i),
            item.source.name,
            new_name,
            status_str,
            confidence,
        )

    console.print(table)
    console.print()

    # Summary
    summary_parts = [f"[green]{ok_count} ready[/green]"]
    if collision_count:
        summary_parts.append(f"[yellow]{collision_count} collisions[/yellow]")
    if skipped_count:
        summary_parts.append(f"[dim]{skipped_count} skipped[/dim]")
    if error_count:
        summary_parts.append(f"[red]{error_count} errors[/red]")
    console.print(f"Summary: {', '.join(summary_parts)}")
    console.print()

    # Dry run mode
    if not execute:
        action = "copy" if output_dir else "rename"
        console.print(f"[dim]Dry run mode. Use --execute to {action} files.[/dim]")
        return

    # Nothing to process
    if ok_count == 0 and collision_count == 0:
        console.print("[yellow]No files to process.[/yellow]")
        return

    # Confirm
    if not yes:
        action = "copy" if output_dir else "rename"
        if collision == CollisionStrategy.SKIP:
            processable = ok_count
        else:
            processable = ok_count + collision_count
        confirmed = typer.confirm(
            f"Proceed with {action} of {processable} file(s)? "
            f"(Collision strategy: {collision.value})"
        )
        if not confirmed:
            console.print("[yellow]Cancelled.[/yellow]")
            raise typer.Exit(0)

    # Execute batch
    console.print()
    copy_mode = output_dir is not None

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        TaskProgressColumn(),
        console=console,
    ) as progress:
        task = progress.add_task("Renaming files...", total=len(items))

        def on_execute_progress(current: int, total: int, item: BatchItem) -> None:
            progress.update(task, completed=current)

        result = execute_batch(
            items,
            collision_strategy=collision,
            copy=copy_mode,
            progress_callback=on_execute_progress,
        )

    # Final summary
    console.print()
    console.print(
        f"[bold]Complete:[/bold] "
        f"[green]{result.successful} successful[/green], "
        f"[yellow]{result.skipped} skipped[/yellow], "
        f"[red]{result.errors} errors[/red]"
    )


@app.command()
def config(
    show: Annotated[
        bool,
        typer.Option(
            "--show",
            "-s",
            help="Show current configuration",
        ),
    ] = False,
) -> None:
    """View or manage configuration."""
    if show:
        settings = get_settings()
        table = Table(title="Current Configuration", show_header=False)
        table.add_column("Setting", style="cyan")
        table.add_column("Value")

        table.add_row("AI Provider", settings.ai_provider)
        table.add_row(
            "Anthropic API Key",
            "[green]set[/green]"
            if settings.anthropic_api_key
            else "[dim]not set[/dim]",
        )
        table.add_row(
            "OpenAI API Key",
            "[green]set[/green]"
            if settings.openai_api_key
            else "[dim]not set[/dim]",
        )
        table.add_row(
            "Gemini API Key",
            "[green]set[/green]"
            if settings.gemini_api_key
            else "[dim]not set[/dim]",
        )
        table.add_row("Ollama URL", settings.ollama_base_url)
        table.add_row(
            "Ollama OCR Model",
            settings.ollama_ocr_model or "[dim]default (deepseek-ocr)[/dim]",
        )
        table.add_row("Template", settings.template)
        table.add_row("Max Authors", str(settings.max_authors))
        table.add_row("Max Filename Length", str(settings.max_filename_length))

        console.print(table)
    else:
        console.print("Use --show to view current configuration.")
        console.print()
        console.print("Configuration can be set via:")
        console.print("  - Environment variables (NAMINGPAPER_*)")
        console.print("  - Config file (~/.namingpaper/config.toml)")


@app.command()
def templates() -> None:
    """Show available filename templates."""
    from namingpaper.template import list_presets

    table = Table(title="Available Templates")
    table.add_column("Name", style="cyan")
    table.add_column("Pattern")
    table.add_column("Example")

    examples = {
        "default": "Smith, Wang, (2023, JFE), Asset pricing....pdf",
        "compact": "Smith, Wang (2023) Asset pricing....pdf",
        "full": "Smith, Wang, (2023, Journal of Financial Economics), Asset pricing....pdf",
        "simple": "Smith, Wang - 2023 - Asset pricing....pdf",
    }

    settings = get_settings()
    current = settings.template

    for name, pattern in list_presets().items():
        display_name = f"[bold]{name} ✓[/bold]" if name == current else name
        table.add_row(display_name, pattern, examples.get(name, ""))

    console.print(table)
    console.print()
    if current not in list_presets():
        console.print(f"[dim]Current template (custom):[/dim] {current}")
    console.print("[dim]Use with: namingpaper batch --template <name|pattern>[/dim]")
    console.print("[dim]Set default: add 'template = \"<name>\"' to ~/.namingpaper/config.toml[/dim]")


@app.command()
def check(
    provider: Annotated[
        str | None,
        typer.Option(
            "--provider",
            "-p",
            help="Provider to check (claude, openai, gemini, ollama, omlx)",
        ),
    ] = None,
) -> None:
    """Check if your environment is set up correctly."""
    import httpx

    settings = get_settings()
    provider_name = provider or settings.ai_provider

    table = Table(title="Setup Check", show_header=True)
    table.add_column("Check", style="cyan")
    table.add_column("Status")
    table.add_column("Details")

    all_ok = True

    table.add_row("Provider", "[green]OK[/green]", provider_name)

    if provider_name == "ollama":
        ocr_model = settings.ollama_ocr_model or "deepseek-ocr"
        text_model = settings.model_name or "qwen3.5:4b"
        base_url = settings.ollama_base_url

        # Check connectivity
        try:
            resp = httpx.get(f"{base_url}/api/tags", timeout=5.0)
            resp.raise_for_status()
            tag_data = resp.json()
            table.add_row("Ollama server", "[green]OK[/green]", base_url)

            # Check models
            available = {m["name"] for m in tag_data.get("models", [])}

            # Text model is required (exact match only)
            if text_model in available:
                table.add_row("Text model", "[green]OK[/green]", text_model)
            else:
                table.add_row("Text model", "[red]MISSING[/red]", f"Run: ollama pull {text_model}")
                all_ok = False

            # OCR model is optional (only used when PDF text extraction is insufficient)
            if ocr_model in available:
                table.add_row("OCR model", "[green]OK[/green]", ocr_model)
            else:
                table.add_row("OCR model", "[yellow]OPTIONAL[/yellow]", f"For scanned PDFs: ollama pull {ocr_model}")
        except (httpx.ConnectError, httpx.HTTPError):
            table.add_row("Ollama server", "[red]FAIL[/red]", f"Cannot connect to {base_url}")
            table.add_row("Text model", "[dim]SKIP[/dim]", "Server not reachable")
            table.add_row("OCR model", "[dim]SKIP[/dim]", "Server not reachable")
            all_ok = False

            console.print(table)
            console.print()
            console.print(
                "[yellow]Ollama is not reachable. To set up:[/yellow]\n"
                "  1. Install Ollama: https://ollama.com/download\n"
                "  2. Start the server: ollama serve\n"
                f"  3. Pull the text model: ollama pull {text_model}\n"
                f"  4. (Optional, for scanned PDFs) ollama pull {ocr_model}\n\n"
                "Or use a different provider: namingpaper rename --provider claude <file>"
            )
            raise typer.Exit(1)
    elif provider_name == "omlx":
        text_model = settings.model_name or "mlx-community/Qwen3.5-4B-MLX-4bit"
        ocr_model = settings.omlx_ocr_model or "mlx-community/DeepSeek-OCR-8bit"
        base_url = settings.omlx_base_url

        try:
            resp = httpx.get(f"{base_url}/v1/models", timeout=5.0)
            resp.raise_for_status()
            table.add_row("oMLX server", "[green]OK[/green]", base_url)
            table.add_row("Text model", "[green]SET[/green]", text_model)
            table.add_row("OCR model", "[yellow]OPTIONAL[/yellow]", ocr_model)
        except (httpx.ConnectError, httpx.HTTPError):
            table.add_row("oMLX server", "[red]FAIL[/red]", f"Cannot connect to {base_url}")
            all_ok = False

            console.print(table)
            console.print()
            console.print(
                "[yellow]oMLX is not reachable. To set up:[/yellow]\n"
                "  1. Install oMLX: brew tap jundot/omlx && brew install omlx\n"
                "  2. Start the server: brew services start omlx\n\n"
                "Or use Ollama instead: namingpaper rename --provider ollama <file>"
            )
            raise typer.Exit(1)
    else:
        # Cloud provider checks
        provider_info = {
            "claude": ("anthropic", settings.anthropic_api_key, "NAMINGPAPER_ANTHROPIC_API_KEY"),
            "openai": ("openai", settings.openai_api_key, "NAMINGPAPER_OPENAI_API_KEY"),
            "gemini": ("google.generativeai", settings.gemini_api_key, "NAMINGPAPER_GEMINI_API_KEY"),
        }

        if provider_name not in provider_info:
            table.add_row("Provider", "[red]UNKNOWN[/red]", f"'{provider_name}' is not a valid provider")
            console.print(table)
            raise typer.Exit(1)

        package, api_key, env_var = provider_info[provider_name]

        # Check package
        try:
            __import__(package)
            table.add_row("Package", "[green]OK[/green]", package)
        except ImportError:
            table.add_row("Package", "[red]MISSING[/red]", f"Run: uv add {package}")
            all_ok = False

        # Check API key
        if api_key:
            table.add_row("API key", "[green]OK[/green]", f"{env_var} is set")
        else:
            table.add_row("API key", "[red]MISSING[/red]", f"Set {env_var}")
            all_ok = False

    console.print(table)
    console.print()

    if all_ok:
        console.print("[green]All checks passed![/green]")
    else:
        console.print("[yellow]Some checks failed. See details above.[/yellow]")
        raise typer.Exit(1)


@app.command()
def uninstall(
    manager: Annotated[
        str,
        typer.Option(
            "--manager",
            "-m",
            help="Package manager to use: auto, uv, pipx, pip",
        ),
    ] = "auto",
    execute: Annotated[
        bool,
        typer.Option(
            "--execute",
            "-x",
            help="Actually run the uninstall command",
        ),
    ] = False,
    yes: Annotated[
        bool,
        typer.Option(
            "--yes",
            "-y",
            help="Skip confirmation prompt",
        ),
    ] = False,
    purge: Annotated[
        bool,
        typer.Option(
            "--purge",
            help="Also remove namingpaper user config/data (~/.namingpaper)",
        ),
    ] = False,
) -> None:
    """Uninstall namingpaper."""
    manager = manager.lower()
    if manager not in {"auto", "uv", "pipx", "pip"}:
        console.print(f"[red]Error:[/red] Invalid manager '{manager}'. Use auto, uv, pipx, or pip.")
        raise typer.Exit(1)

    selected = manager
    if manager == "auto":
        if shutil.which("uv"):
            selected = "uv"
        elif shutil.which("pipx"):
            selected = "pipx"
        else:
            selected = "pip"

    commands = {
        "uv": ["uv", "tool", "uninstall", "namingpaper"],
        "pipx": ["pipx", "uninstall", "namingpaper"],
        "pip": [sys.executable, "-m", "pip", "uninstall", "namingpaper"],
    }
    cmd = commands[selected]
    cmd_display = " ".join(cmd)

    if not execute:
        console.print(f"[blue]Detected manager:[/blue] {selected}")
        console.print(f"[blue]Uninstall command:[/blue] {cmd_display}")
        console.print("[dim]Dry run mode. Use --execute to run it automatically.[/dim]")
        return

    if not yes:
        confirmed = typer.confirm(f"Run uninstall command? {cmd_display}")
        if not confirmed:
            console.print("[yellow]Cancelled.[/yellow]")
            raise typer.Exit(0)

    run_cmd = cmd.copy()
    if selected == "pip" and yes:
        run_cmd.insert(4, "-y")

    result = subprocess.run(run_cmd, capture_output=True, text=True)
    if result.returncode == 0:
        console.print("[green]Uninstall complete.[/green]")
        if result.stdout.strip():
            console.print(result.stdout.strip())
        if not purge:
            return

        config_dir = Path.home() / ".namingpaper"
        if not config_dir.exists():
            console.print("[dim]No user config/data directory found at ~/.namingpaper[/dim]")
            return

        if not yes:
            confirmed = typer.confirm(f"Also delete user config/data directory? {config_dir}")
            if not confirmed:
                console.print("[yellow]Cleanup skipped.[/yellow]")
                return

        try:
            shutil.rmtree(config_dir)
            console.print(f"[green]Removed:[/green] {config_dir}")
        except Exception as e:
            console.print(f"[red]Failed to remove {config_dir}:[/red] {e}")
            raise typer.Exit(1)
        return

    console.print("[red]Uninstall failed.[/red]")
    if result.stderr.strip():
        console.print(result.stderr.strip())
    console.print(f"[yellow]Try running manually:[/yellow] {cmd_display}")
    raise typer.Exit(result.returncode)


@app.command()
def update(
    manager: Annotated[
        str,
        typer.Option(
            "--manager",
            "-m",
            help="Package manager to use: auto, uv, pipx, pip",
        ),
    ] = "auto",
    execute: Annotated[
        bool,
        typer.Option(
            "--execute",
            "-x",
            help="Actually run the update command",
        ),
    ] = False,
    yes: Annotated[
        bool,
        typer.Option(
            "--yes",
            "-y",
            help="Skip confirmation prompt",
        ),
    ] = False,
) -> None:
    """Update namingpaper to the latest version."""
    manager = manager.lower()
    if manager not in {"auto", "uv", "pipx", "pip"}:
        console.print(f"[red]Error:[/red] Invalid manager '{manager}'. Use auto, uv, pipx, or pip.")
        raise typer.Exit(1)

    selected = manager
    if manager == "auto":
        if shutil.which("uv"):
            selected = "uv"
        elif shutil.which("pipx"):
            selected = "pipx"
        else:
            selected = "pip"

    commands = {
        "uv": ["uv", "tool", "upgrade", "namingpaper"],
        "pipx": ["pipx", "upgrade", "namingpaper"],
        "pip": [sys.executable, "-m", "pip", "install", "--upgrade", "namingpaper"],
    }
    cmd = commands[selected]
    cmd_display = " ".join(cmd)

    if not execute:
        console.print(f"[blue]Detected manager:[/blue] {selected}")
        console.print(f"[blue]Update command:[/blue] {cmd_display}")
        console.print("[dim]Dry run mode. Use --execute to run it automatically.[/dim]")
        return

    if not yes:
        confirmed = typer.confirm(f"Run update command? {cmd_display}")
        if not confirmed:
            console.print("[yellow]Cancelled.[/yellow]")
            raise typer.Exit(0)

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode == 0:
        console.print("[green]Update complete.[/green]")
        if result.stdout.strip():
            console.print(result.stdout.strip())
        return

    console.print("[red]Update failed.[/red]")
    if result.stderr.strip():
        console.print(result.stderr.strip())
    console.print(f"[yellow]Try running manually:[/yellow] {cmd_display}")
    raise typer.Exit(result.returncode)


@app.command()
def add(
    path: Annotated[
        Path,
        typer.Argument(
            help="Path to a PDF file or directory",
            exists=True,
            resolve_path=True,
        ),
    ],
    execute: Annotated[
        bool,
        typer.Option(
            "--execute", "-x",
            help="Actually add to library (default is dry-run)",
        ),
    ] = False,
    yes: Annotated[
        bool,
        typer.Option("--yes", "-y", help="Skip confirmation prompts"),
    ] = False,
    copy_mode: Annotated[
        bool,
        typer.Option("--copy", help="Copy file instead of moving"),
    ] = False,
    recursive: Annotated[
        bool,
        typer.Option("--recursive", "-r", help="Scan subdirectories"),
    ] = False,
    provider: Annotated[
        str | None,
        typer.Option("--provider", "-p", help="AI provider"),
    ] = None,
    model: Annotated[
        str | None,
        typer.Option("--model", "-m", help="Override model"),
    ] = None,
    ocr_model: Annotated[
        str | None,
        typer.Option("--ocr-model", help="Override OCR model"),
    ] = None,
    template: Annotated[
        str | None,
        typer.Option("--template", "-t", help="Filename template"),
    ] = None,
    category: Annotated[
        str | None,
        typer.Option("--category", "-c", help="Override category (skip AI categorization)"),
    ] = None,
    parallel: Annotated[
        int,
        typer.Option("--parallel", help="Concurrent extractions for directories (default: 1)"),
    ] = 1,
    filename: Annotated[
        str | None,
        typer.Option("--filename", "-f", help="Override AI-generated filename"),
    ] = None,
    no_rename: Annotated[
        bool,
        typer.Option("--no-rename", help="Keep original filename (categorize only)"),
    ] = False,
    reasoning: Annotated[
        bool | None,
        typer.Option("--reasoning/--no-reasoning", help="Enable/disable reasoning mode"),
    ] = None,
    json_output: Annotated[
        bool,
        typer.Option("--json", help="Output results as JSON"),
    ] = False,
    metadata_json: Annotated[
        str | None,
        typer.Option("--metadata-json", help="Pre-extracted metadata as JSON (skip AI extraction)"),
    ] = None,
) -> None:
    """Add paper(s) to the library: rename, summarize, categorize, and file."""
    import asyncio
    import json
    from namingpaper.database import Database
    from namingpaper.library import add_paper as _add_paper, import_directory

    # Resolve template: CLI flag > config/env > default
    settings = get_settings()
    if template is None:
        template = settings.template

    # Parse pre-extracted metadata JSON
    pre_extracted = None
    if metadata_json:
        try:
            pre_extracted = json.loads(metadata_json)
        except json.JSONDecodeError as e:
            if json_output:
                print(json.dumps({"status": "error", "error": f"Invalid --metadata-json: {e}"}))
            else:
                console.print(f"[red]Error:[/red] Invalid --metadata-json: {e}")
            raise typer.Exit(1)

    with Database() as db:
        if path.is_dir():
            results = asyncio.run(import_directory(
                path, db=db,
                provider_name=provider, model_name=model, ocr_model=ocr_model,
                template=template, copy=copy_mode, auto_yes=yes,
                execute=execute, recursive=recursive, parallel=parallel,
            ))
            added = sum(1 for r in results if r.paper and not r.skipped)
            skipped = sum(1 for r in results if r.skipped)
            errors = sum(1 for r in results if r.error)
            console.print(
                f"\n[bold]Summary:[/bold] "
                f"[green]{added} added[/green], "
                f"[yellow]{skipped} skipped[/yellow], "
                f"[red]{errors} errors[/red]"
            )
        else:
            if path.suffix.lower() != ".pdf":
                if json_output:
                    print(json.dumps({"status": "error", "error": f"Not a PDF file: {path}"}))
                else:
                    console.print(f"[red]Error:[/red] Not a PDF file: {path}")
                raise typer.Exit(1)

            result = asyncio.run(_add_paper(
                path, db=db,
                provider_name=provider, model_name=model, ocr_model=ocr_model,
                template=template, copy=copy_mode, auto_yes=yes,
                execute=execute, category_override=category,
                filename_override=filename, no_rename=no_rename,
                reasoning=reasoning,
                pre_extracted=pre_extracted,
            ))

            if result.skipped and result.existing:
                if json_output:
                    print(json.dumps({
                        "status": "skipped",
                        "existing_id": result.existing.id,
                        "source": str(path),
                    }))
                else:
                    console.print(
                        f"[yellow]Already in library:[/yellow] {result.existing.file_path}"
                    )
                return

            if result.error:
                if json_output:
                    print(json.dumps({"status": "error", "error": result.error, "source": str(path)}))
                else:
                    console.print(f"[red]Error:[/red] {result.error}")
                raise typer.Exit(1)

            if result.paper:
                paper = result.paper

                if json_output:
                    print(json.dumps({
                        "status": "ok",
                        "source": str(path),
                        "paper": {
                            "title": paper.title,
                            "authors": paper.authors,
                            "authors_full": paper.authors_full,
                            "year": paper.year,
                            "journal": paper.journal,
                            "journal_abbrev": paper.journal_abbrev,
                            "summary": paper.summary,
                            "keywords": paper.keywords,
                            "category": paper.category,
                            "filename": Path(paper.file_path).name,
                            "destination": paper.file_path,
                            "confidence": paper.confidence,
                        },
                    }))
                else:
                    table = Table(show_header=False)
                    table.add_column("Field", style="cyan")
                    table.add_column("Value")
                    table.add_row("Title", paper.title)
                    table.add_row("Authors", ", ".join(paper.authors))
                    table.add_row("Year", str(paper.year))
                    table.add_row("Journal", paper.journal)
                    if paper.summary:
                        table.add_row("Summary", paper.summary)
                    if paper.keywords:
                        table.add_row("Keywords", ", ".join(paper.keywords))
                    table.add_row("Category", paper.category or "Unsorted")
                    table.add_row("Destination", paper.file_path)
                    console.print(table)

                    if not execute:
                        console.print("\n[dim]Dry run mode. Use --execute to add to library.[/dim]")


@app.command()
def search(
    query: Annotated[
        str,
        typer.Argument(help="Search query"),
    ],
    author: Annotated[
        str | None,
        typer.Option("--author", help="Filter by author"),
    ] = None,
    year: Annotated[
        str | None,
        typer.Option("--year", help="Filter by year or range (e.g., 2020 or 2020-2024)"),
    ] = None,
    journal: Annotated[
        str | None,
        typer.Option("--journal", help="Filter by journal"),
    ] = None,
    category: Annotated[
        str | None,
        typer.Option("--category", help="Filter by category"),
    ] = None,
    smart: Annotated[
        bool,
        typer.Option("--smart", help="Enable AI semantic search"),
    ] = False,
) -> None:
    """Search the paper library."""
    import asyncio
    from namingpaper.database import Database
    from namingpaper.models import SearchFilter
    from namingpaper.library import search_library, smart_search

    # Parse year filter
    year_from = year_to = None
    if year:
        if "-" in year:
            parts = year.split("-", 1)
            year_from, year_to = int(parts[0]), int(parts[1])
        else:
            year_from = year_to = int(year)

    filters = SearchFilter(
        author=author,
        year_from=year_from,
        year_to=year_to,
        journal=journal,
        category=category,
        smart=smart,
    )

    use_smart = smart or len(query.split()) >= 6

    with Database() as db:
        if use_smart:
            papers = asyncio.run(smart_search(db, query))
        else:
            papers = search_library(db, query=query, filters=filters)

    if not papers:
        console.print("[yellow]No papers found.[/yellow]")
        return

    table = Table(title=f"Results for \"{query}\"")
    table.add_column("ID", style="dim", width=8)
    table.add_column("Year", width=6)
    table.add_column("Authors", max_width=25)
    table.add_column("Category", max_width=25)
    table.add_column("Title", max_width=40)

    for p in papers:
        table.add_row(
            p.id,
            str(p.year),
            ", ".join(p.authors[:3]),
            p.category or "Unsorted",
            p.title[:40] + ("..." if len(p.title) > 40 else ""),
        )

    console.print(table)
    console.print(f"\n{len(papers)} paper(s) found.")


@app.command(name="list")
def list_papers(
    category: Annotated[
        str | None,
        typer.Option("--category", help="Filter by category"),
    ] = None,
    sort: Annotated[
        str,
        typer.Option("--sort", help="Sort by: year, author, title, date-added"),
    ] = "date-added",
    limit: Annotated[
        int,
        typer.Option("--limit", help="Max results to show"),
    ] = 20,
) -> None:
    """List papers in the library."""
    from namingpaper.database import Database

    sort_map = {"date-added": "created_at", "year": "year", "author": "authors", "title": "title"}
    sort_by = sort_map.get(sort, "created_at")

    with Database() as db:
        papers = db.list_papers(category=category, sort_by=sort_by, limit=limit)

    if not papers:
        console.print("[yellow]No papers in library.[/yellow]")
        return

    table = Table(title="Paper Library")
    table.add_column("ID", style="dim", width=8)
    table.add_column("Year", width=6)
    table.add_column("Authors", max_width=25)
    table.add_column("Category", max_width=25)
    table.add_column("Title", max_width=40)

    for p in papers:
        table.add_row(
            p.id,
            str(p.year),
            ", ".join(p.authors[:3]),
            p.category or "Unsorted",
            p.title[:40] + ("..." if len(p.title) > 40 else ""),
        )

    console.print(table)
    console.print(f"\n{len(papers)} paper(s) shown.")


@app.command()
def info(
    paper_id: Annotated[
        str,
        typer.Argument(help="Paper ID"),
    ],
) -> None:
    """Show detailed info for a paper."""
    from namingpaper.database import Database

    with Database() as db:
        paper = db.get_paper(paper_id)

    if not paper:
        console.print(f"[red]Paper not found:[/red] {paper_id}")
        raise typer.Exit(1)

    table = Table(title=f"Paper: {paper_id}", show_header=False)
    table.add_column("Field", style="cyan")
    table.add_column("Value")

    table.add_row("ID", paper.id)
    table.add_row("Title", paper.title)
    table.add_row("Authors", ", ".join(paper.authors))
    if paper.authors_full:
        table.add_row("Authors (full)", ", ".join(paper.authors_full))
    table.add_row("Year", str(paper.year))
    table.add_row("Journal", paper.journal)
    if paper.journal_abbrev:
        table.add_row("Abbreviation", paper.journal_abbrev)
    table.add_row("Category", paper.category or "Unsorted")
    table.add_row("File", paper.file_path)
    if paper.summary:
        table.add_row("Summary", paper.summary)
    if paper.keywords:
        table.add_row("Keywords", ", ".join(paper.keywords))
    if paper.confidence is not None:
        table.add_row("Confidence", f"{paper.confidence:.0%}")
    table.add_row("Added", paper.created_at)
    table.add_row("Updated", paper.updated_at)
    table.add_row("SHA-256", paper.sha256)

    console.print(table)


@app.command()
def remove(
    paper_id: Annotated[
        str,
        typer.Argument(help="Paper ID to remove"),
    ],
    delete_file: Annotated[
        bool,
        typer.Option("--delete-file", help="Also delete the file from disk"),
    ] = False,
    execute: Annotated[
        bool,
        typer.Option("--execute", "-x", help="Actually remove (default is dry-run)"),
    ] = False,
    yes: Annotated[
        bool,
        typer.Option("--yes", "-y", help="Skip confirmation"),
    ] = False,
) -> None:
    """Remove a paper from the library."""
    from namingpaper.database import Database
    from namingpaper.library import remove_paper

    with Database() as db:
        paper = db.get_paper(paper_id)
        if not paper:
            console.print(f"[red]Paper not found:[/red] {paper_id}")
            raise typer.Exit(1)

        console.print(f"Paper: [bold]{paper.title}[/bold]")
        console.print(f"File: {paper.file_path}")

        if not execute:
            console.print("\n[dim]Dry run mode. Use --execute to remove.[/dim]")
            return

        if not yes:
            msg = "Remove from library"
            if delete_file:
                msg += " AND delete file from disk"
            confirmed = typer.confirm(f"{msg}?")
            if not confirmed:
                console.print("[yellow]Cancelled.[/yellow]")
                return

        removed = remove_paper(db, paper_id, delete_file=delete_file)
        if removed:
            console.print("[green]Removed from library.[/green]")
            if delete_file:
                console.print("[green]File deleted.[/green]")


@app.command()
def sync(
    execute: Annotated[
        bool,
        typer.Option("--execute", "-x", help="Apply fixes"),
    ] = False,
    yes: Annotated[
        bool,
        typer.Option("--yes", "-y", help="Skip confirmation"),
    ] = False,
) -> None:
    """Sync library database with filesystem."""
    from namingpaper.database import Database
    from namingpaper.library import sync_library

    with Database() as db:
        untracked, missing, moved = sync_library(db, execute=execute)

    if not untracked and not missing and not moved:
        console.print("[green]Library is in sync.[/green]")
        return

    if moved:
        console.print(f"\n[green]{len(moved)} moved file(s){' updated' if execute else ' detected'}:[/green]")
        for paper, new_path in moved[:10]:
            console.print(f"  {paper.id}: → {new_path}")
        if len(moved) > 10:
            console.print(f"  ... and {len(moved) - 10} more")

    if untracked:
        console.print(f"\n[yellow]{len(untracked)} untracked file(s):[/yellow]")
        for f in untracked[:10]:
            console.print(f"  {f}")
        if len(untracked) > 10:
            console.print(f"  ... and {len(untracked) - 10} more")

    if missing:
        console.print(f"\n[yellow]{len(missing)} missing file(s):[/yellow]")
        for p in missing[:10]:
            console.print(f"  {p.id}: {p.file_path}")
        if len(missing) > 10:
            console.print(f"  ... and {len(missing) - 10} more")

    if not execute:
        console.print("\n[dim]Dry run mode. Use --execute to apply fixes.[/dim]")
        return

    if missing:
        if yes or typer.confirm(f"Remove {len(missing)} missing record(s) from database?"):
            with Database() as db:
                for p in missing:
                    db.delete_paper(p.id)
            console.print(f"[green]Removed {len(missing)} missing record(s).[/green]")

    if untracked:
        console.print(
            f"\n[dim]{len(untracked)} untracked file(s) can be added with:[/dim]"
        )
        console.print("[dim]  namingpaper add <file> --execute[/dim]")


if __name__ == "__main__":
    app()
