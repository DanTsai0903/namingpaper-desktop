# namingpaper

AI-powered academic PDF renamer with a native macOS app and paper library.

**Before:** `1-s2.0-S0304405X13000044-main.pdf`
**After:** `Fama and French, (1993, JFE), Common risk factors in the returns....pdf`

## What's in this project

- **CLI tool** — rename PDFs from the terminal, one at a time or in batch
- **macOS app** — native SwiftUI desktop app with paper library, search, and PDF preview
- **Paper library** — SQLite-backed catalog with AI-generated summaries, categories, and full-text search

## Installation

### CLI

```bash
# Using uv (recommended)
uv tool install namingpaper

# Using pipx
pipx install namingpaper

# With optional cloud providers
uv tool install "namingpaper[openai]"
uv tool install "namingpaper[gemini]"
```

### macOS App

Open `macos/NamingPaper/NamingPaper.xcodeproj` in Xcode and build.

## Quick Start

### CLI

The default provider is Ollama (local, no API key needed). Install from [ollama.com](https://ollama.com), then:

```bash
ollama pull qwen3:8b

# Preview rename (dry run)
namingpaper rename paper.pdf

# Execute rename
namingpaper rename paper.pdf --execute

# Batch rename
namingpaper batch ~/Downloads/papers --execute
```

For cloud providers (Claude, OpenAI, Gemini):

```bash
export NAMINGPAPER_ANTHROPIC_API_KEY=sk-ant-...
namingpaper rename paper.pdf -p claude --execute
```

### macOS App

The app wraps the CLI and adds a visual paper library. Add papers, browse by category, search metadata, and preview PDFs — all from a native interface.

Features:

- Drag-and-drop or file picker to add papers
- AI-extracted metadata with confidence scores
- Category tree sidebar with smart organization
- Full-text fuzzy search across titles, authors, and journals
- Inline PDF preview and editable metadata
- API keys stored in macOS Keychain

## Paper Library

```bash
# Add a paper (rename + summarize + categorize)
namingpaper add paper.pdf --execute

# Search
namingpaper search "risk factors"
namingpaper search --author "Fama" --year 2020-2024

# Browse
namingpaper list --category "Finance/Asset Pricing"
namingpaper info a3f2
namingpaper remove a3f2 --execute
```

Papers are organized into `~/Papers/` (configurable via `NAMINGPAPER_PAPERS_DIR`) with category subfolders.

## CLI Reference

### `namingpaper rename <pdf>`

Rename a single PDF.

| Option | Description |
|--------|-------------|
| `-x, --execute` | Actually rename (default is dry-run) |
| `-y, --yes` | Skip confirmation |
| `-p, --provider` | AI provider: `ollama`, `claude`, `openai`, `gemini` |
| `-m, --model` | Override default model |
| `--ocr-model` | Override Ollama OCR model |
| `-t, --template` | Filename template or preset |
| `-o, --output-dir` | Copy to directory (keeps original) |
| `-c, --collision` | Collision strategy: `skip`, `increment`, `overwrite` |

### `namingpaper batch <directory>`

Rename all PDFs in a directory.

Same options as `rename`, plus:

| Option | Description |
|--------|-------------|
| `-r, --recursive` | Scan subdirectories |
| `-f, --filter` | Glob pattern filter |
| `--parallel N` | Concurrent extractions |
| `--json` | JSON output |

### Other commands

```bash
namingpaper templates    # Show available templates
namingpaper config --show
namingpaper version
namingpaper update --execute --yes
namingpaper uninstall --execute --yes [--purge]
```

## Filename Templates

| Preset | Pattern | Example |
|--------|---------|---------|
| `default` | `{authors}, ({year}, {journal}), {title}` | `Fama and French, (1993, JFE), Common risk....pdf` |
| `compact` | `{authors} ({year}) {title}` | `Fama and French (1993) Common risk....pdf` |
| `full` | `{authors}, ({year}, {journal_full}), {title}` | Uses full journal name |
| `simple` | `{authors} - {year} - {title}` | `Fama and French - 1993 - Common risk....pdf` |

Placeholders: `{authors}`, `{authors_full}`, `{authors_abbrev}`, `{year}`, `{journal}`, `{journal_full}`, `{journal_abbrev}`, `{title}`

## AI Providers

| Provider | Setup | Notes |
|----------|-------|-------|
| **Ollama** (default) | `ollama pull qwen3:8b` | Local, no API key |
| **oMLX** | Apple Silicon Mac | Local MLX inference |
| **Claude** | `NAMINGPAPER_ANTHROPIC_API_KEY` | |
| **OpenAI** | `NAMINGPAPER_OPENAI_API_KEY` | Requires `namingpaper[openai]` |
| **Gemini** | `NAMINGPAPER_GEMINI_API_KEY` | Requires `namingpaper[gemini]` |

## Configuration

Config priority: CLI args > env vars (`NAMINGPAPER_*`) > config file (`~/.namingpaper/config.toml`) > defaults.

```toml
# ~/.namingpaper/config.toml
ai_provider = "ollama"
template = "default"
max_authors = 3
max_filename_length = 200
```

See full env var list with `namingpaper config --show`.

## Development

```bash
git clone https://github.com/DanTsai0903/namingpaper-desktop.git
cd namingpaper-desktop
uv sync --all-extras --dev
uv run pytest -v
```

## Credits

Originally forked from [DanTsai0903/namingpaper](https://github.com/DanTsai0903/namingpaper).

## License

MIT
