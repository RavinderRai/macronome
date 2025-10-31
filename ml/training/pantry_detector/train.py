"""
Train YOLO model for pantry item detection
"""
import shutil
from pathlib import Path
from ultralytics import YOLO
import mlflow
from ml.training.pantry_detector.config import TrainingConfig


def train_detector():
    """Train YOLO model for pantry detection"""
    
    # Load config
    config = TrainingConfig()
    
    # Ensure dataset exists
    if not config.dataset_yaml.exists():
        raise FileNotFoundError(f"Dataset not found at {config.dataset_yaml}")
    
    # Prepare cache dirs for MLflow and pretrained weights
    tracking_dir = (Path(__file__).resolve().parent / "mlruns").resolve()
    tracking_dir.mkdir(parents=True, exist_ok=True)
    mlflow.set_tracking_uri(tracking_dir.as_uri())

    config.weights_cache_dir.mkdir(parents=True, exist_ok=True)
    base_weights_path = config.base_weights_path
    root_weights_path = Path.cwd() / f"{config.model_size}.pt"
    if root_weights_path.exists() and root_weights_path.resolve() != base_weights_path.resolve():
        base_weights_path.unlink(missing_ok=True)
        shutil.move(str(root_weights_path), str(base_weights_path))
    mlflow.set_experiment("pantry-detector")
    
    print("🚀 Starting training with config:")
    print(f"  Model: {config.model_size}")
    print(f"  Epochs: {config.epochs}")
    print(f"  Batch size: {config.batch_size}")
    print(f"  Image size: {config.image_size}")
    print(f"  Device: {config.device}")
    print(f"  Dataset: {config.dataset_yaml}")
    print(f"  Output: {config.model_save_dir}")
    
    with mlflow.start_run():
        # Log hyperparameters
        mlflow.log_params({
            "model": config.model_size,
            "epochs": config.epochs,
            "batch_size": config.batch_size,
            "imgsz": config.image_size,
            "patience": config.patience,
        })
        
        # Load YOLO model (pre-trained on COCO)
        print(f"\n📥 Loading model: {config.model_size}.pt")
        model = YOLO(str(base_weights_path))
        
        # Train the model
        print(f"\n🏋️  Training started...")
        results = model.train(
            data=str(config.dataset_yaml),
            epochs=config.epochs,
            batch=config.batch_size,
            imgsz=config.image_size,
            project=str(config.project_dir),
            name=config.experiment_name,
            save=True,
            save_period=config.save_period,
            patience=config.patience,
            device=config.device,
        )
        
        # Evaluate model
        print(f"\n📊 Evaluating model...")
        metrics = model.val()
        
        # Log metrics to MLflow
        mlflow.log_metrics({
            "mAP50": metrics.box.map50,
            "mAP50-95": metrics.box.map,
            "precision": metrics.box.mp,
            "recall": metrics.box.mr,
        })
        
        print(f"\n📈 Results:")
        print(f"  mAP50: {metrics.box.map50:.3f}")
        print(f"  mAP50-95: {metrics.box.map:.3f}")
        print(f"  Precision: {metrics.box.mp:.3f}")
        print(f"  Recall: {metrics.box.mr:.3f}")
        
        # Export model to ONNX for inference
        print(f"\n📦 Exporting model to ONNX...")
        model.export(format="onnx")
        
        # Log artifacts
        if base_weights_path.exists():
            mlflow.log_artifact(str(base_weights_path))
        if config.model_save_dir.exists():
            mlflow.log_artifacts(str(config.model_save_dir))
        
        print(f"\n✅ Training complete!")
        print(f"   Model saved to: {config.model_save_dir}")
        print(f"   Best weights: {config.weights_path}")
        
        return str(config.weights_path)


if __name__ == "__main__":
    train_detector()
