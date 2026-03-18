## Context

namingpaper currently supports four AI providers: Claude, OpenAI, Gemini (cloud), and Ollama (local). Ollama is the default local provider using its native `/api/generate` and `/api/chat` endpoints. oMLX is a newer local inference server optimized for Apple Silicon that exposes an OpenAI-compatible API at `localhost:8000/v1`. Adding it as a first-class provider gives Mac users a performant local option without the dummy-API-key workaround of routing through the OpenAI provider.

The existing Ollama provider uses `httpx` directly against Ollama's native API. The OpenAI provider uses the `openai` Python SDK. Both patterns exist in the codebase.

## Goals / Non-Goals

**Goals:**
- Add `omlx` as a selectable provider (`--provider omlx`)
- Support the same two-stage pipeline as Ollama (VLM OCR + text model) for scanned PDFs
- No new Python dependencies — use `httpx` (already a core dependency)
- Clear error messages guiding users to install/start oMLX
- Expose in macOS app preferences alongside existing providers

**Non-Goals:**
- Model management (oMLX auto-downloads from HuggingFace — no `pull` equivalent needed)
- Replacing Ollama as the default provider (Ollama remains default for cross-platform compatibility)
- Supporting oMLX's Anthropic Messages endpoint (`/v1/messages`) — the OpenAI-compatible endpoint is sufficient
- Supporting oMLX's embedding or rerank endpoints

## Decisions

### 1. Use `httpx` directly against OpenAI-compatible API (not the `openai` SDK)

Use raw `httpx` calls to `/v1/chat/completions`, matching the Ollama provider's approach.

**Why not the `openai` SDK?** The OpenAI provider requires `pip install namingpaper[openai]` for the SDK. oMLX should work with zero extra dependencies since it's a local provider like Ollama. The OpenAI-compatible API is simple enough that raw HTTP is cleaner than pulling in a full SDK just to set `base_url`.

### 2. Two-stage pipeline mirroring Ollama

Stage 1 (OCR): Send first-page image to a VLM via `/v1/chat/completions` with image content. Stage 2 (metadata): Send extracted text to a text model. Skip stage 1 if text extraction already produced usable content (>100 chars), same as Ollama.

**Why?** Keeps behavior consistent across local providers. Users switching between Ollama and oMLX get the same pipeline logic.

### 3. Default models

- Text model: `mlx-community/Qwen3-8B-4bit` (good balance of quality and speed on Apple Silicon)
- OCR model: `mlx-community/Qwen2.5-VL-7B-Instruct-4bit` (VLM with strong OCR capability)

These are sensible defaults that can be overridden via config (`omlx_ocr_model`) or CLI (`--model`).

### 4. No model unloading

Unlike Ollama where we explicitly unload models (`keep_alive: "0s"`), oMLX handles model lifecycle via LRU eviction automatically. No `aclose()` cleanup needed beyond closing the HTTP client.

### 5. Config settings follow Ollama's pattern

Add `omlx_base_url` and `omlx_ocr_model` to `Settings`, mirroring `ollama_base_url` and `ollama_ocr_model`. Extend `ai_provider` literal to include `"omlx"`.

## Risks / Trade-offs

**[Apple Silicon only]** → Document clearly in error messages. Users on Linux/Windows will see a helpful message suggesting Ollama instead.

**[oMLX is newer/less established than Ollama]** → Keep Ollama as default. oMLX is opt-in via `--provider omlx`.

**[Model name format differs]** → Ollama uses short names (`qwen3:8b`), oMLX uses HuggingFace IDs (`mlx-community/Qwen3-8B-4bit`). Users must use the correct format for each provider. Error messages should clarify this.

**[No model availability check]** → oMLX auto-downloads models on first use, so unlike Ollama we can't pre-check if a model is pulled. First request may be slow if the model needs downloading. Mention this in error handling.
