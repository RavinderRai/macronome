"""
FastAPI service for pantry scanning
"""
from fastapi import FastAPI, File, UploadFile, HTTPException
from PIL import Image
from io import BytesIO
from macronome.ai.pantry_scanner.service import PantryScannerService
from typing import List, Dict
import uvicorn


app = FastAPI(title="Pantry Scanner API", version="0.1.0")
service = PantryScannerService()


@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "service": "pantry-scanner",
        "status": "healthy",
        "endpoints": {
            "/": "health check",
            "/scan": "POST - Scan pantry image",
            "/detect": "POST - Detect items only (no classification)",
        }
    }


@app.post("/scan")
async def scan_pantry(
    file: UploadFile = File(...),
    conf_threshold: float = 0.25,
    crop_padding: int = 10
) -> Dict:
    """
    Full pipeline: Detect items → Crop → Classify
    
    Args:
        file: Image file (JPEG/PNG)
        conf_threshold: Detection confidence threshold (0-1)
        crop_padding: Pixels to add around crops
    
    Returns:
        {
            "num_items": int,
            "items": [
                {
                    "classification": str,
                    "confidence": float,
                    "bounding_box": {...}
                },
                ...
            ]
        }
    """
    try:
        # Read and validate image
        contents = await file.read()
        img = Image.open(BytesIO(contents))
        
        # Convert to RGB if needed
        if img.mode != "RGB":
            img = img.convert("RGB")
        
        # Run pipeline
        results = await service.scan_pantry(img, conf_threshold, crop_padding)
        
        # Format response
        items = []
        for result in results:
            items.append({
                "classification": result["classification"],
                "confidence": result["confidence"],
                "bounding_box": {
                    "x": result["item"].bounding_box.x,
                    "y": result["item"].bounding_box.y,
                    "width": result["item"].bounding_box.width,
                    "height": result["item"].bounding_box.height,
                }
            })
        
        return {
            "num_items": len(items),
            "items": items
        }
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error processing image: {str(e)}")


@app.post("/detect")
async def detect_items(
    file: UploadFile = File(...),
    conf_threshold: float = 0.25
) -> Dict:
    """
    Detect items only (no classification)
    
    Args:
        file: Image file (JPEG/PNG)
        conf_threshold: Detection confidence threshold (0-1)
    
    Returns:
        {
            "num_items": int,
            "items": [
                {
                    "bounding_box": {...},
                    "confidence": float
                },
                ...
            ]
        }
    """
    try:
        # Read and validate image
        contents = await file.read()
        img = Image.open(BytesIO(contents))
        
        # Convert to RGB if needed
        if img.mode != "RGB":
            img = img.convert("RGB")
        
        # Run detection only
        items = await service.get_detections_only(img, conf_threshold)
        
        # Format response
        formatted_items = []
        for item in items:
            formatted_items.append({
                "bounding_box": {
                    "x": item.bounding_box.x,
                    "y": item.bounding_box.y,
                    "width": item.bounding_box.width,
                    "height": item.bounding_box.height,
                },
                "confidence": item.confidence
            })
        
        return {
            "num_items": len(formatted_items),
            "items": formatted_items
        }
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error processing image: {str(e)}")


if __name__ == "__main__":
    uvicorn.run("macronome.ai.pantry_scanner.main:app", host="0.0.0.0", port=8001, reload=True)

