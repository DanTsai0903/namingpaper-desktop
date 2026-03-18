## ADDED Requirements

### Requirement: Paper summarization
The system SHALL generate a short summary (2-4 sentences) of a paper using the existing AI provider infrastructure. The summarization prompt SHALL instruct the AI to read the abstract/introduction and produce a concise description of the paper's contribution.

#### Scenario: Summarize a paper with abstract text
- **WHEN** the PDF content includes abstract text
- **THEN** system generates a 2-4 sentence summary focusing on the paper's main contribution

#### Scenario: Summarize a paper with minimal text
- **WHEN** the PDF content has limited extractable text (e.g., scanned PDF)
- **THEN** system generates a best-effort summary from available content, with lower confidence

### Requirement: Keyword extraction
The system SHALL extract 3-8 descriptive keywords or key phrases from the paper using the AI provider. Keywords SHALL be lowercase, domain-relevant terms (e.g., "asset pricing", "CAPM", "cross-section").

#### Scenario: Extract keywords from a finance paper
- **WHEN** a paper about common risk factors is processed
- **THEN** system returns keywords like ["asset pricing", "risk factors", "size effect", "value effect"]

#### Scenario: Keywords returned as a list
- **WHEN** the AI generates keywords
- **THEN** the result is a list of 3-8 lowercase strings

### Requirement: Combined extraction in single AI call
The system SHALL extract summary and keywords in a single AI call (alongside or after metadata extraction) to minimize API usage and latency. The AI response SHALL be structured JSON with `summary` and `keywords` fields.

#### Scenario: Single call returns summary and keywords
- **WHEN** the system requests summarization for a paper
- **THEN** both summary and keywords are returned from one AI provider call

#### Scenario: Partial result handling
- **WHEN** the AI returns a summary but no keywords (or vice versa)
- **THEN** the system stores whatever was returned and sets missing fields to null/empty

### Requirement: Reuse existing AI provider abstraction
The summarization SHALL use the same `AIProvider` interface and provider selection logic as metadata extraction. No new provider implementations are needed. The provider and model options from the `add` command SHALL apply to summarization.

#### Scenario: Summarization uses configured provider
- **WHEN** user runs `add paper.pdf -p claude --execute`
- **THEN** both metadata extraction and summarization use the Claude provider
