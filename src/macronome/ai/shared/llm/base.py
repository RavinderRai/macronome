from typing import List, Dict, Any
from abc import ABC, abstractmethod
import litellm
from macronome.ai.shared.llm.config import LLMConfig

class BaseLLMClient(ABC):
    """Base LLM client using litellm"""

    def __init__(self, config: LLMConfig):
        self.config = config
        litellm.api_key = config.api_key

    @abstractmethod
    async def generate(self, prompt: str, **kwargs) -> str:
        pass

    def _call_llm(self, messages: List[Dict[str, str]], **override_params: Any) -> str:
        response = litellm.completion(
            model = f"{self.config.provider}/{self.config.model}",
            messages = messages,
            temperature = override_params.get("temperature", self.config.temperature),
            max_tokens = override_params.get("max_tokens", self.config.max_tokens),
            timeout = override_params.get("timeout", self.config.timeout),
        )

        return response.choices[0].message.content