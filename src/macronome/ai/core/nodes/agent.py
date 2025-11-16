from __future__ import annotations

import os
from abc import abstractmethod, ABC
from dataclasses import dataclass
from enum import Enum
from typing import Type, Optional, Union, Any, Sequence

import boto3
from dotenv import load_dotenv
from google.oauth2 import service_account
from httpx import AsyncClient
from openai import AsyncAzureOpenAI
from pydantic import BaseModel
from pydantic_ai import Agent, Tool
from pydantic_ai.mcp import MCPServer
from pydantic_ai.models import Model
from pydantic_ai.models.anthropic import AnthropicModel, AnthropicModelName
from pydantic_ai.models.bedrock import BedrockConverseModel, BedrockModelName
from pydantic_ai.models.gemini import GeminiModelName
from pydantic_ai.models.google import GoogleModel
from pydantic_ai.models.instrumented import InstrumentationSettings
from pydantic_ai.models.openai import OpenAIModelName, OpenAIChatModel
from pydantic_ai.providers.anthropic import AnthropicProvider
from pydantic_ai.providers.bedrock import BedrockProvider
from pydantic_ai.providers.google import GoogleProvider
from pydantic_ai.providers.openai import OpenAIProvider
from pydantic_ai.settings import ModelSettings
from pydantic_ai.tools import AgentDepsT, ToolFuncEither

from macronome.ai.core.nodes.base import Node
from macronome.ai.core.task import TaskContext

load_dotenv()


class ModelProvider(str, Enum):
    OPENAI = "openai"
    AZURE_OPENAI = "azure_openai"
    ANTHROPIC = "anthropic"
    OLLAMA = "ollama"
    BEDROCK = "bedrock"
    GOOGLE_GEMINI = "google"
    GOOGLE_VERTEX_AI = "google_vertex_ai"

@dataclass
class AgentConfig:
    """PydanticAI Agent wrapper.

    Attributes:
        model_provider: Specifies which model provider to use for this agent.
            Supported providers include OpenAI, Azure OpenAI, Anthropic, Gemini, Ollama, and Bedrock.
            The provider you choose determines which set of model names are valid for this agent.
        model_name: The name of the model to use with the specified provider.
            The value should be a model name type that matches the selected model_provider, such as `OpenAIModelName`,
            `AnthropicModelName`, `GeminiModelName`, or `BedrockModelName`.
            This field selects the exact large language model to run your requests with.
        output_type: The type of the output data, used to validate the data returned by the model,
            defaults to `str`.
        instructions: Instructions to use for this agent, you can also register instructions via a function with
            [`instructions`][pydantic_ai.Agent.instructions].
        system_prompt: Static system prompts to use for this agent, you can also register system
            prompts via a function with [`system_prompt`][pydantic_ai.Agent.system_prompt].
        deps_type: The type used for dependency injection, this parameter exists solely to allow you to fully
            parameterize the agent, and therefore get the best out of static type checking.
            If you're not using deps, but want type checking to pass, you can set `deps=None` to satisfy Pyright
            or add a type hint `: Agent[None, <return type>]`.
        name: The name of the agent, used for logging. If `None`, we try to infer the agent name from the call frame
            when the agent is first run.
        model_settings: Optional model request settings to use for this agent's runs, by default.
        retries: The default number of retries to allow before raising an error.
        output_retries: The maximum number of retries to allow for result validation, defaults to `retries`.
        tools: Tools to register with the agent, you can also register tools via the decorators
            [`@agent.tool`][pydantic_ai.Agent.tool] and [`@agent.tool_plain`][pydantic_ai.Agent.tool_plain].
        prepare_tools: custom method to prepare the tool definition of all tools for each step.
            This is useful if you want to customize the definition of multiple tools or you want to register
            a subset of tools for a given step. See [`ToolsPrepareFunc`][pydantic_ai.tools.ToolsPrepareFunc]
        mcp_servers: MCP servers to register with the agent. You should register a [`MCPServer`][pydantic_ai.mcp.MCPServer]
            for each server you want the agent to connect to.
        instrument: Set to True to automatically instrument with OpenTelemetry,
            which will use Logfire if it's configured.
            Set to an instance of [`InstrumentationSettings`][pydantic_ai.agent.InstrumentationSettings] to customize.
            If this isn't set, then the last value set by
            [`Agent.instrument_all()`][pydantic_ai.Agent.instrument_all]
            will be used, which defaults to False.
            See the [Debugging and Monitoring guide](https://ai.pydantic.dev/logfire/) for more info.
    """

    model_provider: ModelProvider
    model_name: Union[
        OpenAIModelName, AnthropicModelName, GeminiModelName, BedrockModelName
    ]
    output_type: Any = str
    instructions: Optional[str] = None
    system_prompt: str | Sequence[str] = ()
    deps_type: Optional[Type[Any]] = None
    name: str | None = None
    model_settings: ModelSettings | None = None
    retries: int = 1
    output_retries: int | None = None
    tools: Sequence[Tool[AgentDepsT] | ToolFuncEither[AgentDepsT, ...]] = ()
    mcp_servers: Sequence[MCPServer] = ()
    instrument: InstrumentationSettings | bool | None = None


class AgentNode(Node, ABC):
    class DepsType(BaseModel):
        pass

    class OutputType(BaseModel):
        pass

    def __init__(self, task_context: TaskContext = None):
        super().__init__(task_context)

        self.__async_client = AsyncClient()
        agent_wrapper = self.get_agent_config()
        self.agent = Agent(
            model=self.__get_model_instance(
                agent_wrapper.model_provider, agent_wrapper.model_name
            ),
            output_type=agent_wrapper.output_type,
            instructions=agent_wrapper.instructions,
            system_prompt=agent_wrapper.system_prompt,
            deps_type=agent_wrapper.deps_type,
            name=agent_wrapper.name,
            model_settings=agent_wrapper.model_settings,
            retries=agent_wrapper.retries,
            output_retries=agent_wrapper.output_retries,
            tools=agent_wrapper.tools,
            mcp_servers=agent_wrapper.mcp_servers,
            instrument=agent_wrapper.instrument,
        )

    @abstractmethod
    def get_agent_config(self) -> AgentConfig:
        pass

    @abstractmethod
    async def process(self, task_context: TaskContext) -> TaskContext:
        pass

    def __get_model_instance(self, provider: ModelProvider, model_name: str) -> Model:
        match provider.value:
            case provider.OPENAI.value:
                return self.__get_openai_model(model_name)
            case provider.AZURE_OPENAI.value:
                return self.__get_azure_openai_model(model_name)
            case provider.ANTHROPIC.value:
                return self.__get_anthropic_model(model_name)
            case provider.OLLAMA.value:
                return self.__get_ollama_model(model_name)
            case provider.BEDROCK.value:
                return self.__get_bedrock_model(model_name)
            case provider.GOOGLE_GEMINI.value:
                return self.__get_google_gemini_model(model_name)
            case provider.GOOGLE_VERTEX_AI.value:
                return self.__get_google_vertex_ai_model(model_name)

    def __get_openai_model(self, model_name) -> Model:
        return OpenAIChatModel(model_name=model_name)

    def __get_azure_openai_model(self, model_name) -> Model:
        client = AsyncAzureOpenAI(
            api_version=os.getenv("AZURE_OPENAI_API_VERSION", "2024-10-21")
        )
        return OpenAIChatModel(
            model_name=model_name,
            provider=OpenAIProvider(openai_client=client),
        )

    def __get_anthropic_model(self, model_name: AnthropicModelName) -> Model:
        return AnthropicModel(
            model_name=model_name,
            provider=AnthropicProvider(http_client=self.__async_client),
        )

    def __get_ollama_model(self, model_name: str) -> Model:
        base_url = os.getenv("OLLAMA_BASE_URL")
        if not base_url:
            raise KeyError("OLLAMA_BASE_URL not set in .env")

        return OpenAIChatModel(
            model_name=model_name, provider=OpenAIProvider(base_url=base_url)
        )

    def __get_bedrock_model(self, model_name: str) -> Model:
        aws_access_key_id = os.getenv("BEDROCK_AWS_ACCESS_KEY_ID")
        aws_secret_access_key = os.getenv("BEDROCK_AWS_SECRET_ACCESS_KEY")
        aws_region = os.getenv("BEDROCK_AWS_REGION")

        bedrock_client = boto3.client(
            "bedrock-runtime",
            region_name=aws_region,
            aws_access_key_id=aws_access_key_id,
            aws_secret_access_key=aws_secret_access_key,
        )
        return BedrockConverseModel(
            model_name=model_name,
            provider=BedrockProvider(bedrock_client=bedrock_client),
        )

    def __get_google_gemini_model(self, model_name: str) -> Model:
        return GoogleModel(
            model_name=model_name,
            provider=GoogleProvider(),
        )

    def __get_google_vertex_ai_model(self, model_name: str) -> Model:
        credentials = service_account.Credentials.from_service_account_file(
            filename=os.getenv("GOOGLE_APPLICATION_CREDENTIALS"),
            scopes=["https://www.googleapis.com/auth/cloud-platform"],
        )
        provider = GoogleProvider(
            credentials=credentials,
            location=os.getenv("GOOGLE_VERTEX_AI_LOCATION", "europe-west1"),
        )
        return GoogleModel(
            model_name=model_name,
            provider=provider,
        )