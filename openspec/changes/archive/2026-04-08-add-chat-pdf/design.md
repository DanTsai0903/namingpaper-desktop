## Context

NamingPaper is a macOS app (SwiftUI, MVVM with @Observable) that manages academic papers in a SQLite library. The paper detail view currently shows metadata on top and a PDFKit preview below. The app already has a multi-provider AI system (Ollama, oMLX, LM Studio, Claude, OpenAI, Gemini) with Keychain-stored API keys and config.toml settings.

The user wants a ChatPDF-style feature: a split-pane view with the PDF on the left and a chat panel on the right, where users can ask questions about the paper and get cited answers. The UI reference (ChatPDF) shows: greeting with bullet-point summary, suggested question cards, a "Summarize this paper" CTA, citation badges (↗1) that link to pages, and a message input bar.

## Goals / Non-Goals

**Goals:**
- Split-pane layout: PDF viewer left, chat panel right (like the ChatPDF reference)
- RAG pipeline: chunk PDF text → embed → retrieve relevant chunks → generate answer with page citations
- Citation navigation: clicking a citation badge scrolls the PDF to the referenced page
- Suggested questions generated after document indexing
- Reuse existing AI provider infrastructure for both embeddings and chat
- Persist chat history and document index per paper locally
- Support both local (Ollama/oMLX/LM Studio) and cloud (Claude/OpenAI/Gemini) providers

**Non-Goals:**
- Multi-document chat (chat across multiple papers at once)
- Flashcard or slide generation (visible in ChatPDF UI but out of scope)
- Cloud-synced chat history
- Custom embedding model selection (use provider defaults)
- Streaming responses (can be added later; initial version waits for full response)

## Decisions

### 1. Layout: Replace detail view with split-pane PDF+Chat

**Decision:** When chat mode is activated, replace the current detail layout (metadata top, PDF bottom) with a horizontal split: PDF viewer on the left, chat panel on the right. A toolbar toggle switches between the current detail view and chat mode.

**Why:** Matches the ChatPDF reference UI. Users need to see the PDF and chat side by side to follow citations. The existing metadata/PDF vertical split doesn't leave room for a chat panel.

**Alternatives considered:**
- Slide-over panel on top of PDF → obscures content, poor for citation following
- Separate window → loses context, harder to coordinate scroll-to-page
- Bottom sheet → too cramped for conversation

### 2. Embedding strategy: In-process cosine similarity over SQLite-stored vectors

**Decision:** Store chunk embeddings as BLOB in SQLite (the existing `library.db`). Compute cosine similarity in Swift at query time. No external vector database.

**Why:** The corpus per paper is small (typically 50-200 chunks for a 20-page PDF). Brute-force cosine similarity over a few hundred vectors is sub-millisecond. Adding FAISS or a vector DB is overkill and adds a native dependency.

**Alternatives considered:**
- FAISS via C bridge → complex build, unnecessary for per-paper scale
- Separate vector DB (Qdrant, ChromaDB) → external process dependency, complex setup
- In-memory only → loses index on app restart, must re-embed every time

### 3. Chunking: Fixed-size with overlap, preserving page boundaries

**Decision:** Extract text per page via PDFKit, then split into ~500-token chunks with ~50-token overlap. Each chunk stores its source page number(s). Page boundaries are preserved (no chunk spans more than 2 pages).

**Why:** Page-level attribution is essential for citation badges. Fixed-size chunks are simple and work well for academic papers. Overlap ensures context isn't lost at boundaries.

### 4. Embeddings: Use the configured AI provider's embedding endpoint

**Decision:** Add an `embed(texts:)` method to the AI provider protocol. For cloud providers (OpenAI, Gemini, Claude), use their native embedding APIs. For local providers (Ollama, oMLX, LM Studio), use their embedding endpoints (Ollama has `/api/embed`, LM Studio has OpenAI-compatible `/v1/embeddings`).

**Why:** Reuses the existing provider infrastructure. Users already have a configured provider — no additional setup needed.

**Fallback:** If a provider doesn't support embeddings (or the model doesn't), fall back to sending the full extracted text as context (no RAG, just stuffing the prompt with PDF text). This works for shorter papers and is a viable degraded mode.

### 5. Chat completion: System prompt with retrieved chunks as context

**Decision:** Build a system prompt that includes the paper metadata + top-k retrieved chunks (k=5-8), then send the user's question. Instruct the model to cite page numbers in the format `[p.N]`. Parse citations in the response to render as clickable badges.

**Why:** Standard RAG approach. The `[p.N]` format is easy to parse with regex and renders cleanly as badges.

### 6. Data model: New tables in existing library.db

**Decision:** Add three tables to `library.db`:
- `paper_chunks` (id, paper_id, page_number, chunk_index, text, embedding BLOB)
- `chat_conversations` (id, paper_id, created_at)
- `chat_messages` (id, conversation_id, role, content, citations JSON, created_at)

**Why:** Keeps everything in one database. The existing `DatabaseService` actor pattern handles thread safety. Schema versioning is already in place.

### 7. UI components (matching ChatPDF reference)

**Decision:** The chat panel includes:
- **Greeting area**: Shows paper title, bullet-point summary (reuse existing AI summary), and "Summarize this paper" button
- **Suggested questions**: 2-3 auto-generated question cards below the greeting
- **Message list**: Scrollable conversation with user/assistant bubbles. Assistant messages render `[p.N]` citations as clickable teal badges
- **Input bar**: Text field with send button at the bottom
- **Citation action**: Tapping a `[p.N]` badge sends a notification that the PDF viewer listens to, scrolling to that page

**Why:** Directly mirrors the ChatPDF reference screenshot provided by the user.

### 8. Indexing lifecycle

**Decision:** Index on first chat open for a paper (not on import). Show a progress indicator during indexing. Cache the index in SQLite — re-index only if the PDF file changes (compare file modification date).

**Why:** Indexing every paper at import time is wasteful. Most papers may never be chatted with. Lazy indexing keeps the app responsive.

## Risks / Trade-offs

- **Local model embedding quality** → Local embedding models (via Ollama) may produce lower-quality vectors than OpenAI/Gemini. Mitigation: the fallback "context stuffing" mode works for short papers; users can switch to a cloud provider for better results.
- **Large PDFs** → Papers over 50 pages may produce many chunks and slow initial indexing. Mitigation: show progress indicator; limit to first 100 pages; chunking is one-time.
- **Provider embedding support** → Not all providers/models support embeddings equally. Mitigation: the fallback mode (send full text as context) ensures the feature works even without embeddings, just with reduced precision for long papers.
- **SQLite BLOB storage for embeddings** → Embedding vectors as BLOBs isn't ideal for large-scale vector search. Mitigation: per-paper scale is tiny (< 200 vectors); brute-force is fine.
- **Citation parsing reliability** → LLMs may not consistently use the `[p.N]` format. Mitigation: include clear instructions in system prompt; parse flexibly (handle `[p. N]`, `[page N]`, etc.).

## Resolved Questions

- **Suggested questions**: Generated at index time (one additional API call when the paper is first indexed). Stored alongside chunks in the database.
- **Conversation persistence**: Support continuing previous conversations. Users can resume a past conversation or start a new one.
