from typing import List
import base64
import asyncio
from macronome.ai.shared.llm.base import BaseLLMClient, LLMConfig

class VisionLLMClient(BaseLLMClient):
    """Vision LLM client using litellm"""

    def __init__(self, config: LLMConfig):
        super().__init__(config)

    async def generate(self, prompt: str, **kwargs) -> str:
        messages = [{"role": "user", "content": prompt}]
        return self._call_llm(messages, **kwargs)

    async def analyze_image(self, image_bytes: bytes, query: str) -> str:
        image_b62 = base64.b64encode(image_bytes).decode("utf-8")

        messages = [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": query},
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg:base64, {image_b62}"}}
                ]
            }
        ]

        return self._call_llm(messages)

    async def analyze_image_batch(self, image_bytes_list: List[bytes], query: str) -> List[str]:
        results = await asyncio.gather(*[self.analyze_image(image_bytes, query) for image_bytes in image_bytes_list])

        return results