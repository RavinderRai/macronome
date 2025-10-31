from __future__ import annotations

from pathlib import Path
from typing import Optional
import mlflow

def get_latest_model_path(
    experiment_name: str,
    tracking_dir: Optional[Path] = None,
    artifact_path: str = "yolo/{experiment_name}/weights/best.pt",
) -> str:
    """
    Get the latest model path from MLflow runs
    
    Args:
        experiment_name: Name of the MLflow experiment
        tracking_dir: MLflow tracking directory. If None, assumes it's in 
                     ml/training/{experiment_name}/mlruns relative to ml/shared
        artifact_path: Path pattern for artifacts within the run. 
                      {experiment_name} will be replaced.
    
    Returns:
        str: Path to the latest model weights
        
    Raises:
        FileNotFoundError: If no MLflow runs found
    """
    # Default tracking directory if not provided
    if tracking_dir is None:
        # ml/shared -> ml -> training/{experiment_name}/mlruns
        tracking_dir = (
            Path(__file__).resolve().parent.parent.parent 
            / "training" 
            / experiment_name 
            / "mlruns"
        )
    
    if not tracking_dir.exists():
        raise FileNotFoundError(
            f"MLflow tracking directory not found at {tracking_dir}. "
            f"Please train the model first."
        )
    
    mlflow.set_tracking_uri(tracking_dir.as_uri())
    
    # Get experiment by name
    try:
        experiment = mlflow.get_experiment_by_name(experiment_name)
        if experiment is None:
            raise FileNotFoundError(
                f"MLflow experiment '{experiment_name}' not found. "
                f"Please train the model first."
            )
    except Exception as e:
        raise FileNotFoundError(f"Failed to get MLflow experiment: {e}")
    
    # Get latest run
    runs = mlflow.search_runs(
        experiment_ids=[experiment.experiment_id],
        order_by=["start_time DESC"],
        max_results=1
    )
    
    if runs.empty:
        raise FileNotFoundError("No MLflow runs found. Please train the model first.")
    
    run_id = runs.iloc[0]["run_id"]
    
    # Format artifact path with experiment name
    formatted_artifact_path = artifact_path.format(experiment_name=experiment_name)
    
    # Construct model path
    model_path = (
        tracking_dir 
        / experiment.experiment_id 
        / run_id 
        / "artifacts" 
        / formatted_artifact_path
    )
    
    if not model_path.exists():
        raise FileNotFoundError(
            f"Model weights not found at {model_path}. "
            "The training run may not have completed successfully."
        )
    
    return str(model_path)