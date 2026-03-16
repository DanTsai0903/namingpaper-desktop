### Requirement: Provider selection
The system SHALL accept `omlx` as a valid value for `--provider` in the CLI and `ai_provider` in config. When selected, the system SHALL instantiate the oMLX provider.

#### Scenario: CLI provider flag
- **WHEN** user runs `namingpaper rename --provider omlx paper.pdf`
- **THEN** the system uses the oMLX provider for metadata extraction

#### Scenario: Config file provider
- **WHEN** `ai_provider = "omlx"` is set in `~/.namingpaper/config.toml`
- **THEN** the system uses the oMLX provider by default

### Requirement: OpenAI-compatible API communication
The oMLX provider SHALL communicate with oMLX's server via HTTP POST to `/v1/chat/completions` using `httpx`. No additional Python packages SHALL be required.

#### Scenario: Text-based metadata extraction
- **WHEN** the provider receives PDF content with usable text (>100 chars)
- **THEN** it sends a single `/v1/chat/completions` request with the text and extraction prompt to the text model

#### Scenario: VLM OCR fallback
- **WHEN** the provider receives PDF content with insufficient text and a first-page image
- **THEN** it first sends the image to the OCR model via `/v1/chat/completions` with image content, then sends the extracted text to the text model for metadata parsing

#### Scenario: No image available
- **WHEN** the provider receives PDF content with insufficient text and no image
- **THEN** it proceeds with whatever text is available, same as the text-based path

### Requirement: Default configuration
The provider SHALL use these defaults:
- Base URL: `http://localhost:8000`
- Text model: `mlx-community/Qwen3-8B-4bit`
- OCR model: `mlx-community/Qwen2.5-VL-7B-Instruct-4bit`

#### Scenario: Defaults applied
- **WHEN** user runs `namingpaper rename --provider omlx paper.pdf` without model overrides
- **THEN** the provider connects to `localhost:8000` and uses the default text model

#### Scenario: Custom model override
- **WHEN** user runs `namingpaper rename --provider omlx --model mlx-community/Llama-3.2-3B-Instruct-4bit paper.pdf`
- **THEN** the provider uses the specified model for the text stage

### Requirement: Config settings
The system SHALL add `omlx_base_url` and `omlx_ocr_model` to the Settings model, configurable via environment variables (`NAMINGPAPER_OMLX_BASE_URL`, `NAMINGPAPER_OMLX_OCR_MODEL`) or config file.

#### Scenario: Custom base URL via environment
- **WHEN** `NAMINGPAPER_OMLX_BASE_URL=http://localhost:9000` is set
- **THEN** the provider connects to port 9000 instead of 8000

#### Scenario: Custom OCR model via config
- **WHEN** `omlx_ocr_model = "mlx-community/Qwen3.5-VL-4bit"` is in config.toml
- **THEN** the provider uses that model for the OCR stage

### Requirement: Error handling
The provider SHALL produce clear, actionable error messages specific to oMLX.

#### Scenario: oMLX server not running
- **WHEN** the provider cannot connect to the oMLX server
- **THEN** it raises a RuntimeError with instructions to install and start oMLX, and suggests Ollama as a cross-platform alternative

#### Scenario: Model not found
- **WHEN** the oMLX server returns a 404 for the requested model
- **THEN** it raises a RuntimeError indicating the model name and that oMLX uses HuggingFace model IDs (e.g., `mlx-community/...`)

#### Scenario: Empty response
- **WHEN** the oMLX server returns an empty response
- **THEN** it raises a RuntimeError indicating the model may not be available

#### Scenario: Request timeout
- **WHEN** the request exceeds the 300s timeout
- **THEN** it raises a RuntimeError noting the model may be downloading or too slow

### Requirement: Raw prompt support
The provider SHALL implement `call_raw(prompt)` for sending arbitrary prompts to the text model.

#### Scenario: Raw prompt call
- **WHEN** `call_raw("summarize this paper")` is called
- **THEN** it sends the prompt via `/v1/chat/completions` and returns the response text

### Requirement: macOS app integration
The macOS app's AI provider preferences SHALL include oMLX as a selectable option with fields for base URL and model configuration.

#### Scenario: Provider selection in preferences
- **WHEN** user opens AI Provider preferences in the macOS app
- **THEN** oMLX appears as a selectable provider alongside Claude, OpenAI, Gemini, and Ollama

#### Scenario: oMLX-specific settings
- **WHEN** user selects oMLX as the provider
- **THEN** the UI shows fields for base URL, text model, and OCR model with appropriate defaults
