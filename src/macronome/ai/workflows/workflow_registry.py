from enum import Enum

from macronome.ai.workflows.meal_recommender_workflow import MealRecommendationWorkflow
from macronome.ai.workflows.pantry_scanner_workflow import PantryScannerWorkflow
from macronome.ai.workflows.chat_workflow import ChatWorkflow

class WorkflowRegistry(Enum):
    MEAL_RECOMMENDER = MealRecommendationWorkflow
    PANTRY_SCANNER = PantryScannerWorkflow
    CHAT = ChatWorkflow