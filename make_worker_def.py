import json

# Read the file
with open('worker-task-def.json', 'r') as f:
    data = json.load(f)

# Create new task definition structure
td = {
    "family": "macronome-worker",
    "networkMode": data.get("networkMode"),
    "executionRoleArn": data.get("executionRoleArn"),
    "containerDefinitions": data.get("containerDefinitions"),
    "requiresCompatibilities": data.get("requiresCompatibilities"),
    "cpu": data.get("cpu"),
    "memory": data.get("memory"),
    "runtimePlatform": data.get("runtimePlatform")
}

# If taskRoleArn exists, add it (it wasn't in the source file but good practice to check)
if "taskRoleArn" in data:
    td["taskRoleArn"] = data["taskRoleArn"]

# Update the container definition
container = td["containerDefinitions"][0]
container["name"] = "macronome-worker"
container["command"] = [
    "celery", 
    "-A", 
    "macronome.backend.worker.config.celery_app", 
    "worker", 
    "--loglevel=info", 
    "--pool=solo"
]

# Update log group to be distinct for worker
if "logConfiguration" in container:
    container["logConfiguration"]["options"]["awslogs-group"] = "/ecs/macronome-worker"

# Save
with open('final-worker-def.json', 'w') as f:
    json.dump(td, f, indent=2)

print("Created final-worker-def.json")
