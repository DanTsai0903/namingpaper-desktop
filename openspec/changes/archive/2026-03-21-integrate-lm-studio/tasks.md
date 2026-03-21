## 1. Config

- [x] 1.1 Add `"lmstudio"` to the `ai_provider` Literal type in `config.py`
- [x] 1.2 Add `lmstudio_base_url`, `lmstudio_model`, and `lmstudio_ocr_model` settings fields to `Settings`

## 2. Provider Implementation

- [x] 2.1 Create `providers/lmstudio.py` with `LMStudioProvider` class — constructor, `_get_client`, async context manager
- [x] 2.2 Implement `_call_lmstudio` HTTP method with error handling (connect error, 404, empty response, timeout)
- [x] 2.3 Implement `extract_metadata` with text-only path and optional VLM OCR fallback
- [x] 2.4 Implement `_ocr_extract` for base64 image via OpenAI vision format
- [x] 2.5 Implement `call_raw` for raw prompt support

## 3. Factory Registration

- [x] 3.1 Add `"lmstudio"` case to `get_provider()` in `providers/__init__.py`

## 4. Testing

- [x] 4.1 Verify existing tests still pass (`uv run pytest`)
