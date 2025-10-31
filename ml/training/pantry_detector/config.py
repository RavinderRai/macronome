"""
Configuration for pantry detector training
"""
from pathlib import Path
from dataclasses import dataclass
import torch


MODULE_ROOT = Path(__file__).resolve().parent


def detect_device():
    """
    Auto-detect best device (MPS for Apple Silicon, CUDA for NVIDIA, CPU otherwise)
    
    Returns:
        str: Device identifier
    """
    if torch.backends.mps.is_available():
        return "mps"  # Apple Silicon GPU
    elif torch.cuda.is_available():
        return "0"  # NVIDIA GPU
    else:
        return "cpu"  # CPU fallback


@dataclass
class TrainingConfig:
    """Configuration for YOLO detector training"""
    
    # Model settings
    model_size: str = "yolov8n"  # yolov8n, yolov8s, yolov8m, yolov8l, yolov8x
    epochs: int = 100
    batch_size: int = 16
    image_size: int = 640
    
    # Data paths
    data_dir: Path = Path("data/processed/yolo_format")
    dataset_yaml: Path = Path("data/processed/yolo_format/data.yaml")
    
    # Output paths
    project_dir: Path = Path("ml/data/models/detector")
    experiment_name: str = "pantry-detector"
    weights_cache_dir: Path = MODULE_ROOT / "weights"
    
    # Training hyperparameters
    patience: int = 50  # Early stopping
    save_period: int = 10  # Save checkpoint every N epochs
    
    # Device - auto-detected
    device: str = detect_device()  # Auto-detect: mps (Apple), cuda (NVIDIA), or cpu
    
    @property
    def model_save_dir(self) -> Path:
        """Get the model save directory"""
        return self.project_dir / self.experiment_name
    
    @property
    def weights_path(self) -> Path:
        """Get path to best weights"""
        return self.model_save_dir / "weights" / "best.pt"

    @property
    def base_weights_path(self) -> Path:
        """Location to cache the pretrained YOLO weights"""
        return self.weights_cache_dir / f"{self.model_size}.pt"
