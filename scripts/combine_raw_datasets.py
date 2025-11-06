from pathlib import Path
import shutil
from collections import defaultdict

# TODO: moved this scripts/ folder to root, so data paths need to be updated


def combine_yolo_datasets(dataset_dirs: list, output_dir: Path):
    """
    Combine multiple YOLO format datasets, simplifying all classes to "food_item"
    
    Args:
        dataset_dirs: List of paths to dataset directories
        output_dir: Path to save combined dataset
    """
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Create output structure
    for split in ["train", "valid", "test"]:
        (output_dir / split / "images").mkdir(parents=True, exist_ok=True)
        (output_dir / split / "labels").mkdir(parents=True, exist_ok=True)
    
    # Copy and remap files
    file_counter = defaultdict(int)
    
    for dataset_idx, dataset_dir in enumerate(dataset_dirs):
        dataset_path = Path(dataset_dir)
        
        for split in ["train", "valid", "test"]:
            split_dir = dataset_path / split
            
            if not split_dir.exists():
                continue
            
            images_dir = split_dir / "images"
            labels_dir = split_dir / "labels"
            
            if not images_dir.exists() or not labels_dir.exists():
                continue
            
            # Process images and labels
            for image_file in images_dir.glob("*"):
                if image_file.suffix.lower() in ['.jpg', '.jpeg', '.png', '.bmp']:
                    # Get corresponding label file
                    label_file = labels_dir / f"{image_file.stem}.txt"
                    
                    if not label_file.exists():
                        continue
                    
                    # Generate unique filename
                    counter = file_counter[split]
                    new_filename = f"img_{counter:04d}"
                    
                    # Copy image
                    shutil.copy(
                        image_file,
                        output_dir / split / "images" / f"{new_filename}{image_file.suffix}"
                    )
                    
                    # Remap all classes to 0 (food_item)
                    remap_to_single_class(
                        label_file,
                        output_dir / split / "labels" / f"{new_filename}.txt"
                    )
                    
                    file_counter[split] += 1
    
    # Create simplified data.yaml
    create_data_yaml(output_dir)
    
    # Print summary
    print(f"\n✅ Combined {len(dataset_dirs)} datasets")
    print(f"📁 Output: {output_dir}")
    print(f"📊 Classes: 1 (food_item)")
    print(f"\nFile counts:")
    for split in ["train", "valid", "test"]:
        images_dir = output_dir / split / "images"
        if images_dir.exists():
            count = len(list(images_dir.glob("*")))
            print(f"  {split}: {count} images")


def remap_to_single_class(label_file: Path, output_file: Path):
    """Remap all classes to class 0 (food_item)"""
    with open(label_file, 'r') as f:
        lines = f.readlines()
    
    remapped_lines = []
    for line in lines:
        parts = line.strip().split()
        if not parts:
            continue
        
        # Set all classes to 0, keep bounding box coordinates
        parts[0] = "0"
        remapped_lines.append(" ".join(parts) + "\n")
    
    # Write remapped labels
    with open(output_file, 'w') as f:
        f.writelines(remapped_lines)


def create_data_yaml(output_dir: Path):
    """Create simplified data.yaml with single class"""
    config = """train: train/images
val: valid/images
test: test/images

nc: 1
names: ['food_item']
"""
    
    with open(output_dir / "data.yaml", 'w') as f:
        f.write(config)
    
    print(f"\n📄 Created data.yaml")


if __name__ == "__main__":
    # Define your datasets
    datasets = [
        Path("data/raw_data/Fridge.v1i.yolov8"),
        Path("data/raw_data/Fridge object detection.v4i.yolov8"),
    ]
    
    # Output directory
    output = Path("data/processed/yolo_format")
    
    # Combine datasets
    combine_yolo_datasets(
        dataset_dirs=[str(d) for d in datasets],
        output_dir=output
    )
    
    print("\n🎉 Done! Dataset is ready for training.")
