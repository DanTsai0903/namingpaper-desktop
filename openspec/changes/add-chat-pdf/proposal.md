## Why

Users store academic papers in NamingPaper but have no way to interrogate their content beyond reading. A ChatPDF-style feature lets users ask natural language questions about a paper and get cited answers — turning a passive library into an active research assistant. This is a natural extension of the existing AI summary capability.

## What Changes

- Add a chat panel to the paper detail view, displayed alongside the existing PDF preview
- Implement document indexing: chunk PDF text and generate embeddings for retrieval
- Implement RAG (Retrieval-Augmented Generation) pipeline: embed user query → retrieve relevant chunks → generate answer with page citations
- Add citation-linked navigation: clicking a page reference in a chat answer scrolls the PDF viewer to that page
- Generate suggested starter questions after indexing
- Support the existing AI provider system (Ollama, Claude, OpenAI, Gemini) for both embeddings and chat completion
- Store conversation history and document index locally per paper

## Capabilities

### New Capabilities
- `pdf-chat`: The conversational UI — chat panel, message display, citation rendering, suggested questions, and interaction with the PDF viewer
- `document-indexing`: PDF text chunking, embedding generation, vector storage, and similarity search for retrieval

### Modified Capabilities
- `paper-detail`: Add a chat panel toggle/tab alongside the existing PDF preview and metadata views

## Impact

- **Views**: New `ChatPanel` view group; modifications to `PaperDetailView` for chat panel integration
- **Models**: New models for chat messages, document chunks, embeddings, and conversation history
- **ViewModels**: New `ChatViewModel` for conversation state and RAG orchestration
- **Data**: Local storage for embeddings index and chat history (SQLite or file-based per paper)
- **Dependencies**: May need a vector similarity library or lightweight local implementation
- **AI Providers**: Reuse existing provider infrastructure; need embedding endpoint support in addition to chat completion
