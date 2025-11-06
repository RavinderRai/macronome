from __future__ import annotations

from PIL.Image import Image
from typing import List
from io import BytesIO
from ml.shared.llm.vision_llm import VisionLLMClient
from ml.shared.llm.base import LLMConfig
from ml.shared.llm.config import get_vision_llm_config
from ml.prompts import load_prompt


class FoodClassifier:
    def __init__(self, config: LLMConfig = None):
        if config is None:
            config = get_vision_llm_config()

        self.llm_client = VisionLLMClient(config)
        self.food_query_prompt = load_prompt("food_query.j2")

    async def food_classifier(self, img: Image) -> str:
        img_bytes = self._convert_image_to_bytes(img)

        result = await self.llm_client.analyze_image(img_bytes, self.food_query_prompt)
        return result

    async def food_classifier_batch(self, imgs: List[Image]) -> List[str]:
        img_bytes_list = [self._convert_image_to_bytes(img) for img in imgs]

        results = await self.llm_client.analyze_image_batch(img_bytes_list, self.food_query_prompt)

        return results

    def _convert_image_to_bytes(self, img: Image) -> bytes:
        img_bytes = BytesIO()
        img.save(img_bytes, format='JPEG')
        img_bytes = img_bytes.getvalue()
        return img_bytes