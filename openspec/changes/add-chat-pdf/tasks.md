## 1. Database Schema

- [x] 1.1 Add `paper_chunks` table (id, paper_id, page_number, chunk_index, text, embedding BLOB, indexed_at) with CASCADE delete on paper_id
- [x] 1.2 Add `paper_index_meta` table (paper_id, pdf_modified_at, suggested_questions JSON, indexed_at) with CASCADE delete
- [x] 1.3 Add `chat_conversations` table (id, paper_id, created_at) with CASCADE delete
- [x] 1.4 Add `chat_messages` table (id, conversation_id, role, content, citations JSON, created_at) with CASCADE delete
- [x] 1.5 Bump schema version and add migration in DatabaseService

## 2. Data Models

- [x] 2.1 Create `PaperChunk` model (id, paperId, pageNumber, chunkIndex, text, embedding)
- [x] 2.2 Create `ChatConversation` model (id, paperId, createdAt)
- [x] 2.3 Create `ChatMessage` model (id, conversationId, role, content, citations, createdAt)
- [x] 2.4 Create `IndexMeta` model (paperId, pdfModifiedAt, suggestedQuestions, indexedAt)

## 3. Document Indexing Service

- [x] 3.1 Create `DocumentIndexingService` actor with PDF text extraction (PDFKit page-by-page)
- [x] 3.2 Implement text chunking (~500 tokens, 50-token overlap, page boundary preservation)
- [x] 3.3 Add embedding generation via AI provider (add `embed(texts:)` to provider protocol)
- [x] 3.4 Implement embedding support for Ollama provider (`/api/embed` endpoint)
- [x] 3.5 Implement embedding support for OpenAI-compatible providers (LM Studio, OpenAI, Gemini)
- [x] 3.6 Implement embedding support for Claude provider (Anthropic has no native embeddings endpoint; Claude throws `embeddingsNotSupported` and relies on the 3.7 context-stuffing fallback)
- [x] 3.7 Add fallback handling when provider doesn't support embeddings (skip embedding, store chunks text-only)
- [x] 3.8 Store chunks and embeddings in `paper_chunks` table
- [x] 3.9 Store index metadata in `paper_index_meta` (pdf modification date, indexed_at)
- [x] 3.10 Add cache check: skip re-indexing if PDF modification date unchanged

## 4. Suggested Question Generation

- [x] 4.1 After indexing, send paper title + first chunk + sample chunks to AI provider to generate 2-3 questions
- [x] 4.2 Store generated questions in `paper_index_meta.suggested_questions`
- [x] 4.3 Handle question generation failure gracefully (index still succeeds)

## 5. Similarity Search

- [x] 5.1 Implement query embedding (embed user question via provider)
- [x] 5.2 Implement cosine similarity computation in Swift over BLOB vectors
- [x] 5.3 Implement top-k retrieval (k=5-8) returning chunks with page numbers and text
- [x] 5.4 Implement fallback: return all chunks in page order when no embeddings exist

## 6. Chat ViewModel

- [x] 6.1 Create `ChatViewModel` (@Observable) with conversation state, messages list, loading state
- [x] 6.2 Implement send message: embed query → retrieve chunks → build system prompt with context → call AI provider
- [x] 6.3 Build system prompt with paper metadata + retrieved chunks + instruction to cite with `[p.N]` format
- [x] 6.4 Implement context-stuffing fallback (send full text when no embeddings)
- [x] 6.5 Implement conversation persistence: load/save conversations and messages from database
- [x] 6.6 Implement "new conversation" (archive current, start fresh)
- [x] 6.7 Implement suggested question tap (send as user message)
- [x] 6.8 Implement "Summarize this paper" action

## 7. Chat Panel UI

- [x] 7.1 Create `ChatPanelView` with greeting area (paper title + bullet summary)
- [x] 7.2 Create suggested question cards below greeting
- [x] 7.3 Create message list with user (right-aligned) and assistant (left-aligned with avatar) bubbles
- [x] 7.4 Implement citation parsing: regex for `[p.N]`, `[p. N]`, `[page N]`, `[pp. N-M]` variants
- [x] 7.5 Render parsed citations as clickable teal badges within message text
- [x] 7.6 Create message input bar with text field, send button, and loading indicator
- [x] 7.7 Implement auto-scroll to latest message
- [x] 7.8 Add indexing progress indicator (shown during first-time indexing)

## 8. Paper Detail Integration

- [x] 8.1 Add "Chat" toggle button to PaperDetailView toolbar (system image: `bubble.left.and.text.bubble.right`, disabled without PDF)
- [x] 8.2 Implement chat mode state toggle in PaperDetailView
- [x] 8.3 Replace detail layout with HSplitView (PDF left, ChatPanelView right) when chat mode is active
- [x] 8.4 Make split divider resizable

## 9. Citation Navigation

- [x] 9.1 Publish citation tap events from ChatPanelView (via NotificationCenter or callback)
- [x] 9.2 Listen for citation events in PDF viewer and scroll to the referenced page
- [x] 9.3 Handle page range citations (scroll to first page of range)

## 10. Xcode Project

- [x] 10.1 Add all new Swift files to the Xcode project (pbxproj)
- [x] 10.2 Build and verify no compile errors
