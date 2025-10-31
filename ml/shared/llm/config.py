import os
from pydantic import BaseModel
from typing import Optional

class LLMConfig(BaseModel):
    provider: str = "openai"
    model: str = "gpt-4o-mini"
    api_key: Optional[str] = None
    temperature: Optional[float] = None
    max_tokens: Optional[int] = None
    timeout: int = 10

def get_vision_llm_config() -> LLMConfig:
    """Factory function to create a vision LLM config"""
    return LLMConfig(
        provider="openai",
        model="gpt-4o",
        temperature=0.0,
    )

def get_text_llm_config() -> LLMConfig:
    """Factory function to create a text LLM config"""
    return LLMConfig(
        provider="openai",
        model="gpt-4o-mini",
        temperature=0.7,
    )
