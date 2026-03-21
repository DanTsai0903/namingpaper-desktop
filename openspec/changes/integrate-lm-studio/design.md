## Context

namingpaper has five AI providers: Claude, OpenAI, Gemini (cloud API-key providers) and Ollama, oMLX (local providers). LM Studio is a popular cross-platform desktop app for running LLMs locally. It exposes an OpenAI-compatible server on `localhost:1234` with `/v1/chat/completions` and `/v1/models` endpoints.

The oMLX provider already implements the exact same pattern we need — `httpx`-based OpenAI-compatible API calls with a two-stage OCR+text pipeline. LM Studio's API is nearly identical, making this a straightforward addition.

## Goals / Non-Goals

**Goals:**
- Add `lmstudio` as a provider option in CLI and config
- Follow the established provider pattern (subclass `AIProvider`, register in factory)
- Support the two-stage VLM OCR + text model pipeline
- Zero new dependencies (reuse `httpx`)

**Non-Goals:**
- macOS app integration (separate change)
- Auto-detection of loaded models in LM Studio
- LM Studio's native REST API (`/api/v0/*`) — we use only the OpenAI-compatible layer

## Decisions

### 1. Reuse oMLX's architecture pattern
**Decision:** Model `LMStudioProvider` closely after `oMLXProvider` — same `httpx.AsyncClient` approach, same two-stage pipeline, same `_parse_response_json` from base class.

**Why:** The APIs are nearly identical (both OpenAI-compatible `/v1/chat/completions`). This minimizes new code and keeps the provider implementations consistent.

**Alternative considered:** Extract a shared `OpenAICompatibleProvider` base class for oMLX and LM Studio. Rejected — the providers have small but meaningful differences (oMLX has model unloading, Qwen3 thinking mode toggle, API key auth; LM Studio has none of these). A shared base would add abstraction without reducing much code, and would couple the two providers' evolution.

### 2. No model unload on close
**Decision:** `LMStudioProvider` does not implement `aclose()` model unloading.

**Why:** LM Studio manages model lifecycle through its GUI. There is no unload endpoint in the OpenAI-compatible API layer. Users load/unload models via the LM Studio app.

### 3. Default text model: `lmstudio-community/qwen2.5-7b-instruct`
**Decision:** Use a well-known, widely-available GGUF model as the default.

**Why:** This model is one of the most downloaded on LM Studio, works on all platforms (GGUF format), and is capable enough for metadata extraction. Users who have different models loaded can override via `--model` or config.

### 4. No default OCR model
**Decision:** Leave `lmstudio_ocr_model` unset by default, unlike oMLX which defaults to a specific VLM.

**Why:** LM Studio users load models manually through the GUI. We can't assume a VLM is loaded. When no OCR model is configured, the provider skips the OCR stage and uses whatever text was extracted from the PDF — matching the behavior when `content.first_page_image` is absent. Users who want OCR can set `lmstudio_ocr_model` in config.

### 5. Error messages reference LM Studio GUI
**Decision:** Connection errors direct users to download LM Studio from `lmstudio.ai` and start the local server from the app.

**Why:** Unlike Ollama (CLI-based) or oMLX (brew-based), LM Studio is a GUI app. Error messages should match the user's mental model of how they interact with it.

## Risks / Trade-offs

- **[Model not loaded]** → LM Studio requires models to be manually loaded. If the user has the server running but no model loaded, the request may fail with an unhelpful error. Mitigation: clear error message suggesting they load the model in the LM Studio app.
- **[Port conflict]** → Default port 1234 is common. If another service uses it, the user gets a confusing error. Mitigation: error message includes the base URL and suggests checking `lmstudio_base_url` config.
- **[No vision model guarantee]** → Unlike oMLX where we set a default VLM, LM Studio users may not have a VLM available. Mitigation: OCR is opt-in (no default OCR model); text-only path works without it.

## Open Questions

None — the implementation is straightforward given the existing oMLX pattern.
