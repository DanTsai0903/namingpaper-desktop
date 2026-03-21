## ADDED Requirements

### Requirement: Provider selection
The system SHALL accept `lmstudio` as a valid value for `--provider` in the CLI and `ai_provider` in config. When selected, the system SHALL instantiate the LM Studio provider.

#### Scenario: CLI provider flag
- **WHEN** user runs `namingpaper rename --provider lmstudio paper.pdf`
- **THEN** the system uses the LM Studio provider for metadata extraction

#### Scenario: Config file provider
- **WHEN** `ai_provider = "lmstudio"` is set in `~/.namingpaper/config.toml`
- **THEN** the system uses the LM Studio provider by default

### Requirement: OpenAI-compatible API communication
The LM Studio provider SHALL communicate with LM Studio's server via HTTP POST to `/v1/chat/completions` using `httpx`. No additional Python packages SHALL be required.

#### Scenario: Text-based metadata extraction
- **WHEN** the provider receives PDF content with usable text (>100 chars)
- **THEN** it sends a single `/v1/chat/completions` request with the text and extraction prompt to the text model

#### Scenario: VLM OCR fallback
- **WHEN** the provider receives PDF content with insufficient text and a first-page image
- **THEN** it first sends the image to the OCR model via `/v1/chat/completions` with base64-encoded image content using the OpenAI vision format (`image_url` with `data:image/png;base64,...`), then sends the extracted text to the text model for metadata parsing

#### Scenario: No image available
- **WHEN** the provider receives PDF content with insufficient text and no image
- **THEN** it proceeds with whatever text is available, same as the text-based path

### Requirement: Default configuration
The provider SHALL use these defaults:
- Base URL: `http://localhost:1234`
- Text model: `lmstudio-community/qwen2.5-7b-instruct`
- OCR model: not set (single-model mode by default; users can configure a VLM model for OCR)

#### Scenario: Defaults applied
- **WHEN** user runs `namingpaper rename --provider lmstudio paper.pdf` without model overrides
- **THEN** the provider connects to `localhost:1234` and uses the default text model

#### Scenario: Custom model override
- **WHEN** user runs `namingpaper rename --provider lmstudio --model my-org/custom-model paper.pdf`
- **THEN** the provider uses the specified model for the text stage

### Requirement: Config settings
The system SHALL add `lmstudio_base_url`, `lmstudio_model`, and `lmstudio_ocr_model` to the Settings model, configurable via environment variables (`NAMINGPAPER_LMSTUDIO_BASE_URL`, `NAMINGPAPER_LMSTUDIO_MODEL`, `NAMINGPAPER_LMSTUDIO_OCR_MODEL`) or config file.

#### Scenario: Custom base URL via environment
- **WHEN** `NAMINGPAPER_LMSTUDIO_BASE_URL=http://localhost:5000` is set
- **THEN** the provider connects to port 5000 instead of 1234

#### Scenario: Custom OCR model via config
- **WHEN** `lmstudio_ocr_model = "publisher/some-vlm-model"` is in config.toml
- **THEN** the provider uses that model for the OCR stage

### Requirement: Error handling
The provider SHALL produce clear, actionable error messages specific to LM Studio.

#### Scenario: LM Studio server not running
- **WHEN** the provider cannot connect to the LM Studio server
- **THEN** it raises a RuntimeError with instructions to download LM Studio and start the local server, and suggests Ollama as an alternative

#### Scenario: Model not loaded
- **WHEN** the LM Studio server returns a 404 or error for the requested model
- **THEN** it raises a RuntimeError indicating the model name and that the model must be downloaded and loaded in LM Studio

#### Scenario: Empty response
- **WHEN** the LM Studio server returns an empty response
- **THEN** it raises a RuntimeError indicating the model may not be loaded or available

#### Scenario: Request timeout
- **WHEN** the request exceeds the 300s timeout
- **THEN** it raises a RuntimeError noting the model may still be loading or the input may be too large

### Requirement: Raw prompt support
The provider SHALL implement `call_raw(prompt)` for sending arbitrary prompts to the text model.

#### Scenario: Raw prompt call
- **WHEN** `call_raw("summarize this paper")` is called
- **THEN** it sends the prompt via `/v1/chat/completions` and returns the response text
