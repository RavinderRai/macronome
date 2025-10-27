from typing import List
import base64
from ml.shared.llm.base import BaseLLMClient, LLMConfig

class VisionLLMClient(BaseLLMClient):
    """Vision LLM client using litellm"""

    def __init__(self, config: LLMConfig):
        super().__init__(config)

    async def generate(self, prompt: str, **kwargs) -> str:
        return super()._call_llm(prompt, **kwargs)