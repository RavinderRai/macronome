from typing import List, Dict, Any, Optional
from abc import ABC, abstractmethod
from pydantic import BaseModel
import litellm
from litellm import completion
from ml.shared.llm.config import LLM_DEFAULT_TIMEOUT

class LLMConfig(BaseModel):
    provider: str = "openai"
    model: str = "gpt-4o-mini"
    api_key: Optional[str] = None
    temperature: Optional[float] = None
    max_tokens: Optional[int] = None
    timeout: int = LLM_DEFAULT_TIMEOUT

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