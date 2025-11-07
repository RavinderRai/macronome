from pathlib import Path

import frontmatter
from jinja2 import Environment, FileSystemLoader, StrictUndefined, TemplateError, meta

"""
Prompt Management Module

This module provides functionality for loading and rendering prompt templates with frontmatter.
It uses Jinja2 for template rendering and python-frontmatter for metadata handling,
implementing a singleton pattern for template environment management.
"""


class PromptManager:
    """Manager class for handling prompt templates and their metadata.

    This class provides functionality to load prompt templates from files,
    render them with variables, and extract template metadata and requirements.
    It implements a singleton pattern for the Jinja2 environment to ensure
    consistent template loading across the application.

    Attributes:
        _env: Class-level singleton instance of Jinja2 Environment

    Example:
        # Render a prompt template with variables
        prompt = PromptManager.get_prompt("greeting", name="Alice")

        # Get template metadata and required variables
        info = PromptManager.get_template_info("greeting")
    """

    _env = None

    @classmethod
    def _get_env(cls) -> Environment:
        """Gets or creates the Jinja2 environment singleton.

        Returns:
            Configured Jinja2 Environment instance

        Note:
            Uses StrictUndefined to raise errors for undefined variables,
            helping catch template issues early.
        """
        if cls._env is None:
            templates_dir = Path(__file__).parent
            cls._env = Environment(
                loader=FileSystemLoader(str(templates_dir)),
                undefined=StrictUndefined,
            )
        return cls._env

    @staticmethod
    def get_prompt(template: str, **kwargs) -> str:
        """Loads and renders a prompt template with provided variables.

        Args:
            template: Name of the template file (with or without .j2 extension)
            **kwargs: Variables to use in template rendering

        Returns:
            Rendered template string

        Raises:
            ValueError: If template rendering fails
            FileNotFoundError: If template file doesn't exist
        """
        env = PromptManager._get_env()
        # Handle .j2 extension automatically
        if not template.endswith(".j2"):
            template = f"{template}.j2"
        template_path = template
        
        # Get the source file path
        source, filename, _ = env.loader.get_source(env, template_path)
        
        # Load frontmatter if present, otherwise use content as-is
        with open(filename, 'r', encoding='utf-8') as file:
            post = frontmatter.load(file)

        # If there's no frontmatter, post.content will be the full file content
        # If there is frontmatter, post.content will be the content after frontmatter
        template_obj = env.from_string(post.content)

        try:
            return template_obj.render(**kwargs)
        except TemplateError as e:
            raise ValueError(f"Error rendering template: {str(e)}")

    @staticmethod
    def get_template_info(template: str) -> dict:
        """Extracts metadata and variable requirements from a template.

        Args:
            template: Name of the template file (with or without .j2 extension)

        Returns:
            Dictionary containing:
                - name: Template name
                - description: Template description from frontmatter
                - author: Template author from frontmatter
                - variables: List of required template variables
                - frontmatter: Raw frontmatter metadata dictionary

        Raises:
            FileNotFoundError: If template file doesn't exist
        """
        env = PromptManager._get_env()
        # Handle .j2 extension automatically
        if not template.endswith(".j2"):
            template = f"{template}.j2"
        template_path = template
        
        # Get the source file path
        source, filename, _ = env.loader.get_source(env, template_path)
        
        with open(filename, 'r', encoding='utf-8') as file:
            post = frontmatter.load(file)

        ast = env.parse(post.content)
        variables = meta.find_undeclared_variables(ast)

        return {
            "name": template.replace(".j2", ""),  # Clean name for display
            "description": post.metadata.get("description", "No description provided"),
            "author": post.metadata.get("author", "Unknown"),
            "variables": list(variables),
            "frontmatter": post.metadata,
        }

