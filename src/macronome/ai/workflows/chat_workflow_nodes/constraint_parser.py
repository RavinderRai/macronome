"""
Constraint Parser Node

Parses constraints from user message and updates user_preferences in the database.
Loads existing preferences, merges with new constraints, and saves back to DB.
"""
from typing import Any, Dict
from pydantic_core import to_jsonable_python

from macronome.ai.core.nodes.agent import AgentNode, AgentConfig, ModelProvider
from macronome.ai.core.task import TaskContext
from macronome.ai.prompts import PromptManager
from macronome.ai.schemas.chat_schema import ChatRequest, ConstraintParserOutput


class ConstraintParser(AgentNode):
    """
    Parses and updates user constraints from chat message.
    
    Loads existing user_preferences from DB, parses new constraints,
    merges them, and updates the database.
    
    Input: ChatRequest + existing user_preferences from DB
    Output: ConstraintParserOutput with updated constraints and confirmation message
    """
    
    class OutputType(AgentNode.OutputType):
        """ConstraintParser outputs ConstraintParserOutput + history"""
        model_output: ConstraintParserOutput
        history: Any
    
    def get_agent_config(self) -> AgentConfig:
        """
        Configure the agent for constraint parsing.
        
        Uses gpt-4o for accurate constraint extraction and categorization.
        """
        return AgentConfig(
            model_provider=ModelProvider.OPENAI,
            model_name="gpt-4o",
            output_type=ConstraintParserOutput,
            system_prompt="You are a constraint parsing assistant that extracts and categorizes meal preferences.",
            name="ConstraintParser",
            retries=2,
        )
    
    async def process(self, task_context: TaskContext) -> TaskContext:
        """
        Parse constraints from user message and update DB.
        
        Args:
            task_context: Contains ChatRequest and user_preferences from DB
            
        Returns:
            TaskContext with updated constraints saved
        """
        request: ChatRequest = task_context.event
        
        # Get existing user preferences from request (loaded by service layer)
        existing_prefs: Dict[str, Any] = request.user_preferences or {}
        
        # Render the prompt with user message, chat history, and existing preferences
        prompt = PromptManager.get_prompt(
            "constraint_parser",
            message=request.message,
            chat_history=request.chat_history,
            existing_default_constraints=existing_prefs.get("default_constraints", {}),
            existing_dietary_restrictions=existing_prefs.get("dietary_restrictions", []),
            existing_custom_constraints=existing_prefs.get("custom_constraints", {}),
            existing_disliked_ingredients=existing_prefs.get("disliked_ingredients", []),
            existing_favorite_cuisines=existing_prefs.get("favorite_cuisines", []),
        )
        
        # Run the agent to parse and merge constraints
        result = await self.agent.run(user_prompt=prompt)
        
        # Get parsed output
        parsed_output: ConstraintParserOutput = result.output
        
        # Store the updated constraints in task_context for DB update by service layer
        task_context.metadata["updated_constraints"] = parsed_output.updated_constraints.model_dump()
        
        # Store output with message history
        history = to_jsonable_python(result.all_messages())
        output = self.OutputType(model_output=parsed_output, history=history)
        self.save_output(output)
        
        return task_context

