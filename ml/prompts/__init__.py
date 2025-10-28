from pathlib import Path
from jinja2 import Environment, FileSystemLoader
from typing import Any, Dict

PROMPTS_DIR = Path(__file__).parent
env = Environment(loader=FileSystemLoader(str(PROMPTS_DIR)))

def load_prompt(template_name: str, **kwargs: Any) -> str:
    """
    Load and render a Jinja2 prompt template
    
    Args:
        template_name: Name of the template file (with or without .j2)
        **kwargs: Variables to pass to the template
    
    Returns:
        str: Rendered prompt
    
    Example:
        prompt = load_prompt("food_query.j2", context="pantry scanning")
    """
    if not template_name.endswith(".j2"):
        template_name += ".j2"

    template = env.get_template(template_name)
    return template.render(**kwargs)