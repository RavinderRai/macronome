"""
Prompt Management Module

This module provides functionality for loading and rendering prompt templates with frontmatter.
It uses Jinja2 for template rendering and python-frontmatter for metadata handling.
"""

from .manager import PromptManager

__all__ = ["PromptManager"]