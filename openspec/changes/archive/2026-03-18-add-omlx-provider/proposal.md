## Why

oMLX is an Apple Silicon-optimized LLM inference server that offers significant performance advantages over Ollama on Mac (tiered SSD KV caching, continuous batching, simultaneous LLM/VLM serving). It exposes an OpenAI-compatible API at `localhost:8000/v1`, making it a natural alternative local provider for namingpaper users on macOS. Adding first-class support avoids the need for users to manually set dummy API keys and base URLs via the OpenAI provider workaround.

## What Changes

- Add a new `omlx` provider that communicates with oMLX's OpenAI-compatible API (`/v1/chat/completions`)
- Support VLM-based OCR via oMLX (models like Qwen3.5-VL) using the same two-stage pipeline as Ollama
- Add `omlx` to the provider registry (`get_provider()`) and config settings (`ai_provider` literal, `omlx_base_url`, `omlx_ocr_model`)
- Add `omlx` as an option in the macOS app's AI provider preferences

## Capabilities

### New Capabilities
- `omlx-provider`: oMLX provider implementation with OpenAI-compatible API integration, VLM OCR support, model auto-detection, and Apple Silicon-specific error messaging

### Modified Capabilities

## Impact

- `src/namingpaper/providers/` — new `omlx.py` module
- `src/namingpaper/providers/__init__.py` — add `omlx` case to `get_provider()`
- `src/namingpaper/config.py` — add `omlx_base_url`, `omlx_ocr_model` settings; extend `ai_provider` literal
- `src/namingpaper/cli.py` — add `omlx` to provider choices
- `macos/` — add oMLX option to AI provider preferences UI
- `pyproject.toml` — no new dependencies needed (uses `httpx` already available)
