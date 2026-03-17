## 1. Config & Provider Registry

- [x] 1.1 Add `omlx_base_url` (default `http://localhost:8000`) and `omlx_ocr_model` (default `None`) to `Settings` in `config.py`; extend `ai_provider` literal to include `"omlx"`
- [x] 1.2 Add `omlx` case to `get_provider()` in `providers/__init__.py`, passing base URL, model, and OCR model from settings
- [x] 1.3 Add `omlx` to CLI provider choices in `cli.py`

## 2. Provider Implementation

- [x] 2.1 Create `src/namingpaper/providers/omlx.py` with `oMLXProvider(AIProvider)` class, `__init__` accepting model, base_url, and ocr_model params with defaults
- [x] 2.2 Implement `_call_omlx()` helper — HTTP POST to `/v1/chat/completions` via `httpx` with error handling (connection refused, 404, timeout, empty response)
- [x] 2.3 Implement `_ocr_extract()` — send first-page image as base64 data URL in OpenAI vision format to the OCR model
- [x] 2.4 Implement `_parse_metadata()` — send text + extraction prompt to the text model, parse JSON response
- [x] 2.5 Implement `extract_metadata()` — two-stage pipeline: skip OCR if text >100 chars, otherwise OCR then parse
- [x] 2.6 Implement `call_raw()` — send arbitrary prompt to text model and return response text

## 3. macOS App Integration

- [x] 3.1 Add oMLX as a provider option in `AIProviderPrefsView.swift` with fields for base URL, text model, and OCR model
- [x] 3.2 Wire oMLX provider settings through `ConfigService` and `CLIService`

## 4. Testing

- [x] 4.1 Add unit tests for `oMLXProvider` — mock httpx responses for text extraction, OCR, error cases
- [x] 4.2 Verify `get_provider("omlx")` returns an `oMLXProvider` instance with correct defaults
