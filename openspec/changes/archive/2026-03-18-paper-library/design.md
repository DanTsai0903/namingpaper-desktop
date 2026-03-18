## Context

`namingpaper` currently provides strong PDF metadata extraction and safe rename workflows, but it does not retain extracted metadata after a rename operation. The `paper-library` change introduces persistent library capabilities while preserving the CLI-first behavior and safety guarantees already present in the project.

This change is cross-cutting: it adds storage (SQLite), new orchestrated workflows (`add`, `search`, `info`, etc.), AI-powered summary/categorization steps, and integration with an external web UI (Filestash). The proposal also sets a strict boundary: Filestash handles file-centric UX (browse/preview/share/manage), while `namingpaper` owns paper semantics (metadata extraction, summary, categorization, search ranking).

Constraints and stakeholders:
- Existing users rely on current `rename` and `batch`; behavior must remain backward-compatible.
- Users want local-first operation and ownership of paper folders.
- The implementation should avoid a custom frontend stack and reuse Filestash for UI.
- The system must stay safe by default for filesystem operations.

## Goals / Non-Goals

**Goals:**
- Add a local SQLite-backed paper library (`~/.namingpaper/library.db`) for persistent metadata.
- Provide unified `add` workflow: rename -> summarize/keywords -> category suggestion -> file placement -> DB persistence.
- Support fast keyword search (FTS5) and optional smart/semantic ranking using existing AI providers.
- Keep current rename pipeline and provider abstractions intact.
- Integrate with Filestash as the UI layer without requiring a custom web app in this repo.
- Preserve user-owned folder model where nested folders under `papers_dir` represent categories.
- Keep safety-by-default behavior: dry-run by default, `--execute` required for mutations.

**Non-Goals:**
- Building a custom SPA/backend server UI in this change.
- Forking or modifying Filestash source code.
- Replacing CLI workflows with UI-only flows.
- Implementing enterprise-grade identity/access management inside `namingpaper` (delegated to Filestash/environment).

## Decisions

1. **Use SQLite + FTS5 as the library store**
- Decision: Store paper records, summaries, keywords, categories, file paths, and hashes in SQLite with FTS5 virtual tables for keyword search.
- Rationale: Local-first, dependency-light, portable, and aligned with CLI usage.
- Alternatives considered:
  - JSON files: easy to start but weak query/index capabilities and migration story.
  - PostgreSQL: stronger concurrency but unnecessary operational overhead for local tool use.

2. **Preserve existing rename/extraction pipeline and layer library orchestration on top**
- Decision: `add` reuses extractor/formatter/renamer, then runs summarization/categorization and DB persistence.
- Rationale: Minimizes regression risk and avoids duplicating proven logic.
- Alternatives considered:
  - New parallel ingest stack: higher risk of divergence and bugs.

3. **Execution semantics follow existing safety model**
- Decision: `add`/`import` are dry-run by default; `--execute` is required for filesystem moves/copies and DB writes. On execute, file placement defaults to move; `--copy` is opt-in.
- Rationale: Aligns with existing namingpaper safety expectations while still supporting archival workflows.
- Alternatives considered:
  - Execute-by-default: faster but higher accidental mutation risk.
  - Copy-by-default: safer but causes frequent duplicates and unclear canonical location.

4. **Dedup policy is hash-first and deterministic**
- Decision: Use SHA-256 content hash as default dedup key. If hash already exists, skip ingest and return existing record/path.
- Rationale: Stable identity independent of filename/metadata quality and cheap to enforce.
- Alternatives considered:
  - Metadata-only dedup: brittle when extraction is partial/inconsistent.
  - Metadata+hash hybrid default: more complex behavior with little v1 benefit.

5. **Category model derived from filesystem under `papers_dir`**
- Decision: Categories are represented by nested subfolders; DB stores normalized category path strings.
- Rationale: Keeps source of truth visible to users and Filestash; no hidden taxonomy store.
- Alternatives considered:
  - DB-only categories: creates drift between UI folders and internal metadata.

6. **Filestash as external UI boundary**
- Decision: Treat Filestash as a deployable external component mounted to `papers_dir`; no in-repo frontend.
- Rationale: Fast delivery, less maintenance, and robust file-manager UX out of the box.
- Alternatives considered:
  - Build custom FastAPI + Vite app: more control but high implementation and maintenance cost.
  - Fork Filestash: maximum control with significant long-term upgrade burden.

7. **Hybrid search model (keyword-first + optional smart reranking)**
- Decision: Default to FTS5 keyword search; invoke smart search with explicit `--smart` or auto-trigger for queries with 6+ words.
- Rationale: Keeps baseline fast/offline-capable while supporting better relevance for ambiguous queries.
- Alternatives considered:
  - AI-only search: expensive and slower.
  - Keyword-only search: weaker experience for semantic queries.

8. **Incremental schema migration strategy**
- Decision: Version DB schema and apply ordered migrations on startup/library command entry.
- Rationale: Safe evolution of data model as library capabilities expand.
- Alternatives considered:
  - Drop-and-recreate DB: unacceptable data loss risk.

## Risks / Trade-offs

- [Risk] Metadata/file drift (DB path differs from actual file location after external moves in Filestash) -> Mitigation: first-class `sync` command in this change plus path update on known move operations.
- [Risk] AI summary/categorization quality variance -> Mitigation: keep user confirmation for category, store confidence/trace fields, allow manual override.
- [Risk] Search consistency issues between FTS index and base tables -> Mitigation: transactional writes and migration/integrity checks.
- [Risk] Concurrency/locking in SQLite during batch imports -> Mitigation: single-writer transaction batching, retry policy for lock contention.
- [Risk] Filestash feature mismatch for paper-specific fields -> Mitigation: keep authoritative paper search in `namingpaper search`; add optional Filestash plugin/API integration later if needed.
- [Risk] Dependency on external Filestash deployment -> Mitigation: make integration optional; CLI workflows remain fully usable without Filestash.

## Migration Plan

1. Introduce DB schema + migration runner and add startup checks in library commands.
2. Implement library domain models and repository layer (CRUD, dedup hash, FTS indexing).
3. Implement `add` orchestration using existing rename pipeline plus summary/categorization and file placement.
4. Add CLI commands for list/search/info/remove/import/sync with backward-compatible defaults.
5. Add folder-discovery and category normalization logic from `papers_dir`.
6. Document Filestash deployment/profile for mounting `papers_dir` and clarify boundary with `namingpaper` features.
7. Rollout: keep legacy commands unchanged; library commands are additive.

Rollback strategy:
- Disable new library commands if severe issue occurs.
- Existing `rename`/`batch` remains unaffected.
- Preserve DB file for recovery; migrations are forward-only with backups before destructive steps.

## Open Questions

- Should `namingpaper` ship a helper command for Filestash bootstrap/config generation, or keep integration purely documented?
- Which metadata fields must be mandatory in v1 records when extraction is partial/fails?
