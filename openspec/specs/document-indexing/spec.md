# Capability: document-indexing

## Purpose

Indexes paper PDFs into vector embeddings for RAG-based chat queries, with lazy indexing, caching, and suggested question generation.

## Requirements

### Requirement: PDF text extraction and chunking

The system SHALL extract text from a paper's PDF page-by-page using PDFKit. The extracted text SHALL be split into chunks of approximately 500 tokens with 50-token overlap. Each chunk SHALL record its source page number(s). No chunk SHALL span more than 2 pages.

#### Scenario: Standard PDF chunking

- **WHEN** a 20-page PDF is indexed
- **THEN** the text is extracted per page and split into ~500-token chunks with page attribution

#### Scenario: Short PDF

- **WHEN** a PDF has fewer than 500 tokens total
- **THEN** a single chunk is created containing all the text

#### Scenario: Page boundary preservation

- **WHEN** a chunk boundary falls mid-page
- **THEN** the chunk records only the page(s) its text originates from, spanning at most 2 pages

### Requirement: Embedding generation

The system SHALL generate vector embeddings for each text chunk using the configured AI provider's embedding endpoint. Embeddings SHALL be stored as BLOBs in the `paper_chunks` table in `library.db`.

#### Scenario: Embed with cloud provider

- **WHEN** the configured provider is OpenAI, Gemini, or Claude
- **THEN** chunks are embedded via the provider's native embedding API

#### Scenario: Embed with local provider

- **WHEN** the configured provider is Ollama, oMLX, or LM Studio
- **THEN** chunks are embedded via the provider's local embedding endpoint

#### Scenario: Provider lacks embedding support

- **WHEN** the configured provider or model does not support embeddings
- **THEN** indexing completes without embeddings; the system falls back to context-stuffing mode for chat queries

### Requirement: Lazy indexing

Document indexing SHALL occur on first chat mode activation for a paper, not at paper import time. A progress indicator SHALL be displayed during indexing. The index SHALL be cached — re-indexing SHALL only occur if the PDF file's modification date has changed.

#### Scenario: First chat open triggers indexing

- **WHEN** user opens chat mode for a paper that has not been indexed
- **THEN** indexing begins with a progress indicator

#### Scenario: Cached index

- **WHEN** user opens chat mode for a previously indexed paper whose PDF has not changed
- **THEN** the cached index is used without re-indexing

#### Scenario: PDF modified since last index

- **WHEN** user opens chat mode and the PDF's modification date is newer than the index
- **THEN** the paper is re-indexed

### Requirement: Suggested question generation

At index time, the system SHALL send the paper's title, abstract (first chunk), and a sample of chunk texts to the AI provider to generate 2-3 suggested questions. The questions SHALL be stored in the database alongside the index.

#### Scenario: Questions generated at index time

- **WHEN** indexing completes successfully
- **THEN** 2-3 suggested questions are generated and stored

#### Scenario: Question generation fails

- **WHEN** the AI provider fails to generate suggested questions
- **THEN** indexing still completes successfully; the chat panel shows no suggested questions

### Requirement: Similarity search

The system SHALL support querying the document index by embedding a user query and computing cosine similarity against all stored chunk embeddings for a paper. The top-k chunks (k=5-8) with highest similarity SHALL be returned, along with their page numbers and text.

#### Scenario: Retrieve relevant chunks

- **WHEN** a user query is embedded and compared against a paper's chunk embeddings
- **THEN** the top 5-8 most similar chunks are returned with page numbers

#### Scenario: No embeddings available

- **WHEN** a similarity search is attempted but the paper has no embeddings
- **THEN** all chunks are returned in page order (fallback for context-stuffing)

### Requirement: Database schema

The system SHALL add the following tables to `library.db`:
- `paper_chunks` (id, paper_id, page_number, chunk_index, text, embedding BLOB, indexed_at)
- `chat_conversations` (id, paper_id, created_at)
- `chat_messages` (id, conversation_id, role, content, citations JSON, created_at)
- `paper_index_meta` (paper_id, pdf_modified_at, suggested_questions JSON, indexed_at)

Schema changes SHALL use the existing schema versioning mechanism.

#### Scenario: Tables created on upgrade

- **WHEN** the app launches with an older schema version
- **THEN** the new tables are created via schema migration

#### Scenario: Data integrity

- **WHEN** a paper is removed from the library
- **THEN** its chunks, conversations, messages, and index metadata are also deleted (CASCADE)
