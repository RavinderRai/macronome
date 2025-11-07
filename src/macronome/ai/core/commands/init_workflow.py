import re
from pathlib import Path


class WorkflowInitCommand:
    def __init__(self):
        self.workflow_name = self.get_valid_snake_case_input()

        self.workflow_name_camel_case = self.to_camel_case_with_first_cap(
            self.workflow_name
        )
        self.workflows_path = Path(__file__).parent.parent.parent / "workflows"
        self.schemas_path = Path(__file__).parent.parent.parent / "schemas"

    def get_valid_snake_case_input(self) -> str:
        # Regular expression to validate snake_case
        snake_case_pattern = r"^[a-z][a-z0-9_]*[a-z0-9]$"
        while True:
            user_input = input("Enter the workflow name (snake_case): ").strip()

            # Remove '_workflow' or 'workflow' suffix if present
            if user_input.endswith("_workflow"):
                user_input = user_input[:-9]  # Remove '_workflow'
            elif user_input.endswith("workflow"):
                user_input = user_input[:-8]  # Remove 'workflow'

            # Validate if the result is still valid snake_case
            if re.match(snake_case_pattern, user_input):
                return user_input

            print(
                "Invalid input. Please enter a valid snake_case name, "
                "excluding the 'workflow' suffix (e.g., 'example_workflow')."
            )

    def to_camel_case_with_first_cap(self, snake_str: str) -> str:
        components = snake_str.strip("_").split("_")
        return "".join(word.capitalize() for word in components)

    def create_workflow_nodes(self):
        folder_path = self.workflows_path / f"{self.workflow_name}_workflow_nodes"
        folder_path.mkdir(parents=False, exist_ok=True)

        file_path = folder_path / "__init__.py"
        if not file_path.exists():
            print("Creating file:" + str(file_path))
            file_path.write_text("")
        else:
            print(file_path, "already exists. Skipping.")

        file_path = folder_path / "initial_node.py"
        if not file_path.exists():
            print("Creating file:" + str(file_path))
            file_path.write_text("""from core.nodes.base import Node
from core.task import TaskContext


class InitialNode(Node):
    async def process(self, task_context: TaskContext) -> TaskContext:
        return task_context
            """)
        else:
            print(file_path, "already exists. Skipping.")

    def create_workflow(self):
        file_path = self.workflows_path / f"{self.workflow_name}_workflow.py"
        if not file_path.exists():
            print("Creating file:" + str(file_path))
            file_path.write_text(f"""from core.schema import WorkflowSchema, NodeConfig
from core.workflow import Workflow
from schemas.{self.workflow_name}_schema import {self.workflow_name_camel_case}EventSchema
from workflows.{self.workflow_name}_workflow_nodes.initial_node import InitialNode


class {self.workflow_name_camel_case}Workflow(Workflow):
    workflow_schema = WorkflowSchema(
        description="",
        event_schema={self.workflow_name_camel_case}EventSchema,
        start=InitialNode,
        nodes=[
            NodeConfig(
                node=InitialNode,
                connections=[],
                description="",
                concurrent_nodes=[],
            ),
        ],
    )
    """)
        else:
            print(file_path, "already exists. Skipping.")

    def create_schema(self):
        file_path = self.schemas_path / f"{self.workflow_name}_schema.py"
        if not file_path.exists():
            print("Creating file:" + str(file_path))
            file_path.write_text(f"""from pydantic import BaseModel
    
    
class {self.workflow_name_camel_case}EventSchema(BaseModel):
    pass""")
        else:
            print(file_path, "already exists. Skipping.")

    def run(self):
        self.create_workflow_nodes()
        self.create_workflow()
        self.create_schema()

def main():
    WorkflowInitCommand().run()


if __name__ == "__main__":
    main()