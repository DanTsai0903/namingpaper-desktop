## Why

LM Studio is one of the most popular local LLM inference tools, with a large user base across macOS, Windows, and Linux. It exposes an OpenAI-compatible API server, making it a natural fit alongside the existing Ollama and oMLX providers. Adding LM Studio support lets users who already run models through LM Studio use namingpaper without switching tools or needing API keys.

## What Changes

- Add a new `lmstudio` AI provider that communicates via LM Studio's OpenAI-compatible `/v1/chat/completions` endpoint
- Register `lmstudio` as a valid provider in the factory (`get_provider`) and config (`ai_provider` literal)
- Add `lmstudio_base_url` and `lmstudio_model` settings to config (env vars + config file)
- Support the same two-stage pipeline (VLM OCR + text model) when vision models are available
- Add `lmstudio_ocr_model` setting for the OCR stage
- Implement `call_raw()` for raw prompt support

## Capabilities

### New Capabilities
- `lmstudio-provider`: LM Studio AI provider — provider selection, OpenAI-compatible API communication, default configuration, config settings, error handling, raw prompt support

### Modified Capabilities

_(none — this is a new provider following the existing pattern; no existing spec behavior changes)_

## Impact

- **Code**: New `providers/lmstudio.py` module, additions to `providers/__init__.py` (factory), `config.py` (settings + Literal type)
- **Dependencies**: None — uses `httpx` which is already a dependency
- **CLI**: `--provider lmstudio` becomes a valid option
- **Config**: New `NAMINGPAPER_LMSTUDIO_*` env vars and `lmstudio_*` config keys
- **macOS app**: Provider picker should include LM Studio (separate change)
