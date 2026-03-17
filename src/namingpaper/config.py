"""Configuration management for namingpaper."""

import tomllib
from pathlib import Path
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment and config file."""

    model_config = SettingsConfigDict(
        env_prefix="NAMINGPAPER_",
        env_file=".env",
        extra="ignore",
        populate_by_name=True,
    )

    # API keys
    anthropic_api_key: str | None = Field(default=None)
    openai_api_key: str | None = Field(default=None)
    gemini_api_key: str | None = Field(default=None)

    # Provider selection
    ai_provider: Literal["claude", "openai", "gemini", "ollama", "omlx"] = Field(
        default="ollama", alias="provider"
    )

    # Extraction settings
    model_name: str | None = Field(
        default=None,
        alias="model",
        description="Fallback model override (prefer provider-specific model fields)",
    )
    max_text_chars: int = Field(
        default=8000, ge=100, le=100000, description="Max characters of text to send to AI"
    )
    min_confidence: float = Field(
        default=0.5,
        ge=0.0,
        le=1.0,
        description="Minimum confidence threshold; documents below this are skipped",
    )

    # Claude settings
    claude_model: str | None = Field(default=None, description="Model for Claude provider")

    # OpenAI settings
    openai_model: str | None = Field(default=None, description="Model for OpenAI provider")

    # Gemini settings
    gemini_model: str | None = Field(default=None, description="Model for Gemini provider")

    # Ollama settings
    ollama_base_url: str = Field(
        default="http://localhost:11434",
        description="Base URL for Ollama API",
    )
    ollama_model: str | None = Field(default=None, description="Text model for Ollama")
    ollama_ocr_model: str | None = Field(
        default=None, description="Override OCR model for Ollama (default: deepseek-ocr)"
    )

    # oMLX settings
    omlx_base_url: str = Field(
        default="http://localhost:8000",
        description="Base URL for oMLX API",
    )
    omlx_api_key: str | None = Field(
        default=None, description="API key for oMLX (if --api-key is set on the server)"
    )
    omlx_model: str | None = Field(default=None, description="Text model for oMLX")
    omlx_ocr_model: str | None = Field(
        default=None, description="Override OCR model for oMLX (default: mlx-community/Qwen2.5-VL-7B-Instruct-4bit)"
    )

    # Filename formatting
    max_authors: int = Field(
        default=3, ge=1, description="Max authors before using 'et al'"
    )
    max_filename_length: int = Field(
        default=200, ge=20, le=255, description="Maximum filename length"
    )

    # Library settings
    papers_dir: Path = Field(
        default=Path.home() / "Papers",
        description="Root directory for organized papers",
    )

    @classmethod
    def load(cls) -> "Settings":
        """Load settings from environment and config file."""
        config_path = Path.home() / ".namingpaper" / "config.toml"
        file_settings = {}

        if config_path.exists():
            try:
                with open(config_path, "rb") as f:
                    file_settings = tomllib.load(f)
            except tomllib.TOMLDecodeError as e:
                raise ValueError(
                    f"Invalid TOML in config file '{config_path}': {e}"
                ) from e
            except PermissionError as e:
                raise ValueError(
                    f"Cannot read config file '{config_path}': permission denied"
                ) from e
            except OSError as e:
                raise ValueError(
                    f"Cannot read config file '{config_path}': {e}"
                ) from e

        return cls(**file_settings)


# Global settings instance
_settings: Settings | None = None


def get_settings() -> Settings:
    """Get or create the global settings instance."""
    global _settings
    if _settings is None:
        _settings = Settings.load()
    return _settings


def reset_settings() -> None:
    """Reset settings (useful for testing)."""
    global _settings
    _settings = None
