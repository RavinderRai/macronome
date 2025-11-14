from enum import Enum

from workflows.meal_recommender_workflow import MealRecommendationWorkflow
from workflows.pantry_scanner_workflow import PantryScannerWorkflow

class WorkflwRegistry(Enum):
    MEAL_RECOMMENDER = MealRecommendationWorkflow
    PANTRY_SCANNER = PantryScannerWorkflow