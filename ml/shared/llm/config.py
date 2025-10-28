import os
from ml.shared.llm.base import LLMConfig

LLM_DEFAULT_TIMEOUT = 60

def get_vision_llm_config() -> LLMConfig:
    """Factory function to create a vision LLM config"""
    return LLMConfig(
        provider="openai",
        model="gpt-4o",
        temperature=0.0,
        timeout=LLM_DEFAULT_TIMEOUT,
    )

def get_text_llm_config() -> LLMConfig:
    """Factory function to create a text LLM config"""
    return LLMConfig(
        provider="openai",
        model="gpt-4o-mini",
        temperature=0.7,
        timeout=LLM_DEFAULT_TIMEOUT,
    )
