from pydantic import BaseModel


class BoundingBox(BaseModel):
    x: int
    y: int
    width: int
    height: int

class PantryItem(BaseModel):
    id: str
    bounding_box: BoundingBox
    confidence: float
