# Project Context

## Purpose
`namingpaper` is a CLI-first academic PDF management tool. It renames papers to
a standardized format and is expanding to persist/search extracted metadata in a
local library database, while using Filestash as the web UI for file browsing
and operations.

Canonical filename format:

```
author names_(year, journal abbrev)_topic.ext
```

Examples:
- `Smith, Wang_(2023, JFE)_Asset pricing anomalies.pdf`
- `Fama, French_(1993, JFE)_Common risk factors in stock returns.pdf`

The tool can process a single file or batch-rename all papers in a folder, and
new library workflows add summarize/categorize/search on top of rename.

## Tech Stack
- **Python 3.14** — language runtime
- **uv** — package management and virtual-env tooling
- **Pytest** — test framework
- **Typer** — CLI framework
- **Pydantic / Pydantic Settings** — typed models and configuration priority
- **SQLite (FTS5)** — local paper metadata/search store (library capability)
- **Filestash** — external web UI layer for browsing/previewing/managing files

## Project Conventions

### Code Style
- PEP 8 throughout
- Type hints on all public functions and class signatures
- One clear responsibility per module — keep files focused and small

### Architecture Patterns
- `namingpaper` package is the CLI entry point; subcommands added as the tool grows
- Core logic separated from CLI:
  - **pdf_reader** — extracts text or renders pages from PDFs
  - **providers** — abstract AI provider interface with implementations (Claude/OpenAI/Gemini/Ollama)
  - **extractor** — sends PDF content to AI, parses structured response
  - **formatter** — builds the canonical filename string from metadata
  - **renamer** — performs the actual filesystem rename with safety checks
  - **library/database (new capability)** — persists metadata, summaries, keywords, categories, and search index
- Config priority: CLI args > env vars (`NAMINGPAPER_*`) > `~/.namingpaper/config.toml` > defaults
- Filestash is treated as the UI surface, not a custom frontend inside this repo

### Testing Strategy
- Pytest as the single test framework
- Tests live in a top-level `tests/` directory
- All filesystem operations in tests use `tmp_path` fixtures — never touch real
  user directories
- Unit tests cover naming-rule evaluation; integration tests cover full
  CLI round-trips (dry-run and live)

### Git Workflow
- Feature branches off `main`
- Squash or rebase before merging — keep history linear
- Use OpenSpec proposals for any new capability, breaking change, or
  architectural shift before coding begins

## Domain Context
The core domain is **academic paper metadata and organization**:

- **Authors** — one or more author surnames, comma-separated
- **Year** — publication year (4 digits)
- **Journal abbreviation** — standard short form (e.g., JFE, RFS, AER, QJE)
- **Topic** — a short descriptive title or the paper's actual title
- **Summary/keywords/category** — derived metadata used for library search and filing

### Metadata source (MVP)
**AI-powered extraction** — extract text/images from the PDF (title page,
abstract, headers) and send to an AI API to identify:
- Author names
- Publication year
- Journal name (and derive abbreviation)
- Paper topic/title

The tool supports multiple AI providers (Claude, OpenAI, Gemini) via a
configurable backend. User selects their provider and supplies an API key.

Workflow (rename path):
1. Extract content from PDF (text or render first page as image)
2. Send to AI with a structured prompt asking for the fields
3. Parse AI response into metadata struct
4. Let user confirm/edit before renaming

Fallback: if AI extraction fails or user has no API key, prompt for manual entry.

Workflow (library path):
1. Rename with existing pipeline
2. Generate summary + keywords
3. Suggest/confirm category
4. Persist metadata in SQLite and place file into user-owned paper folders

## Important Constraints
- **Safe by default** — never overwrite a file without explicit confirmation or
  a `--dry-run` flag showing the planned changes first
- **Collision-aware** — if a rename would collide with an existing file, warn
  and skip (or offer an auto-increment strategy)
- **Cross-platform paths** — must handle macOS, Linux, and Windows path
  conventions correctly
- Symlinks should be reported but not silently followed during a rename
- **UI boundary** — Filestash handles web file UX; paper-specific semantics stay in namingpaper CLI/library logic

## External Dependencies

**Required:**
- **pypdf / pdfplumber / pymupdf** — PDF content extraction
- **Pillow** — image processing for vision workflows

**AI providers (user installs one or more):**
- **anthropic** — Claude API client
- **openai** — OpenAI API client
- **google-generativeai** — Gemini API client
- **ollama** — local model backend (default path in this project)

**Future/optional:**
- **httpx** — for API calls to CrossRef/Semantic Scholar or external services
- Filestash plugin/API integration components for deeper metadata-aware UI links

## Configuration
The tool needs:
- **AI provider selection** — which backend to use (claude/openai/gemini)
- **API key** — stored in env var or config file (never committed to repo)
- **Journal abbreviation mappings** — optional lookup table for full name → abbrev
