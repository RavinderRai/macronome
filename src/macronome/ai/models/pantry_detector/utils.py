"""
Utility functions for training and validation
"""
from pathlib import Path
from PIL import Image
import numpy as np


def visualize_predictions(model, image_path: Path, save_path: Path = None):
    """
    Visualize model predictions on an image
    
    Args:
        model: Trained YOLO model
        image_path: Path to image
        save_path: Optional path to save visualization
    """
    results = model(str(image_path))
    
    # Plot results
    plotted = results[0].plot()
    
    if save_path:
        Image.fromarray(plotted).save(save_path)
    
    return plotted


def count_dataset_files(data_dir: Path):
    """Count files in train/val/test splits"""
    counts = {}
    
    for split in ["train", "valid", "test"]:
        split_dir = data_dir / split / "images"
        if split_dir.exists():
            counts[split] = len(list(split_dir.glob("*")))
        else:
            counts[split] = 0
    
    return counts


def print_dataset_summary(data_dir: Path):
    """Print summary of dataset"""
    counts = count_dataset_files(data_dir)
    
    print("\n📊 Dataset Summary:")
    print(f"  Train images: {counts.get('train', 0)}")
    print(f"  Valid images: {counts.get('valid', 0)}")
    print(f"  Test images: {counts.get('test', 0)}")
    print(f"  Total: {sum(counts.values())} images")

