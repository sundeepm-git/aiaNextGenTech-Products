# Base classes for MCP Azure Security
# mcp/base.py
from fastapi import FastAPI
from typing import Callable, Dict, Any
import logging

class McpTool:
    def __init__(self, name: str, handler: Callable, schema: Dict[str, Any]):
        self.name = name
        self.handler = handler
        self.schema = schema

class McpServer:
    def __init__(self, name: str):
        self.name = name
        self.app = FastAPI(title=name)
        self.tools: dict[str, McpTool] = {}
        self.logger = logging.getLogger(name)

    def register_tool(self, name: str, schema: Dict[str, Any]):
        def decorator(func: Callable):
            self.tools[name] = McpTool(name, func, schema)
            return func
        return decorator

    async def call_tool(self, tool_name: str, args: Dict[str, Any]):
        tool = self.tools.get(tool_name)
        if not tool:
            raise ValueError(f"Unknown tool: {tool_name}")
        self.logger.info(f"Calling tool {tool_name} with args {args}")
        return await tool.handler(**args)