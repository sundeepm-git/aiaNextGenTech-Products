# Architecture Overview

This document provides an architectural overview of the aiaNextGenTech-Products repository.

## System Design

The repository follows a modular architecture designed to support both GenAI (Generative AI) and AgenticAI (Agentic AI) applications.

### Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                     Application Layer                        │
│                   (Your AI Applications)                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Agents Layer                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  BaseAgent   │  │  Specialized │  │   Custom     │     │
│  │   (Base)     │  │    Agents    │  │   Agents     │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Models Layer                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   Prompts    │  │    Config    │  │  Evaluation  │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Utilities Layer                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   Logging    │  │    Config    │  │  Validation  │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    External Services                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   OpenAI     │  │  Anthropic   │  │  VectorDBs   │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

## Directory Structure

### `/agents`
Contains agent implementations and base classes.

- **Purpose**: Define autonomous AI agents
- **Key Files**: 
  - `base.py`: BaseAgent abstract class
  - `__init__.py`: Package initialization
- **Usage**: Extend `BaseAgent` to create custom agents

### `/models`
Contains GenAI models, prompts, and configurations.

- **Purpose**: Manage LLM interactions and prompts
- **Key Subdirectories**:
  - `prompts/`: Prompt templates and engineering
- **Usage**: Store and version control prompts and model configs

### `/utils`
Shared utilities and helper functions.

- **Purpose**: Common functionality across the project
- **Key Files**:
  - `config.py`: Configuration management
  - `logging.py`: Logging utilities
- **Usage**: Import utilities as needed

### `/examples`
Sample implementations and tutorials.

- **Purpose**: Demonstrate usage patterns
- **Key Files**:
  - `simple_agent.py`: Basic agent template
  - `base_agent_example.py`: BaseAgent usage
- **Usage**: Reference for building your own agents

### `/tests`
Test suite for the project.

- **Purpose**: Ensure code quality and correctness
- **Key Files**:
  - `conftest.py`: Shared fixtures
  - `test_*.py`: Test modules
- **Usage**: Run with pytest

### `/configs`
Configuration files for different environments.

- **Purpose**: Environment-specific settings
- **Usage**: Load configs based on environment

### `/docs`
Documentation and guides.

- **Purpose**: User and developer documentation
- **Usage**: Reference for setup and usage

## Design Principles

### 1. Modularity
Each component is self-contained and can be used independently.

### 2. Extensibility
Base classes (like `BaseAgent`) allow easy extension for custom implementations.

### 3. Configurability
Use environment variables and config files for flexibility.

### 4. Testability
All components are designed to be easily testable.

## Agent Architecture

### BaseAgent Class
All agents inherit from the `BaseAgent` abstract class:

```python
class MyAgent(BaseAgent):
    def process(self, input_data):
        # Implement custom logic
        return output
```

### Key Methods
- `process()`: Main processing method (must be implemented)
- `reset()`: Reset agent state
- `add_to_history()`: Track conversation
- `get_history()`: Retrieve conversation history
- `log()`: Logging with verbose mode

## Data Flow

1. **Input** → Agent receives input data
2. **Processing** → Agent processes using LLM or custom logic
3. **History** → Interaction is logged in conversation history
4. **Output** → Agent returns processed result

## Integration Points

### LLM Providers
- OpenAI (GPT-4, GPT-3.5)
- Anthropic (Claude)
- Custom models via API

### Vector Databases
- ChromaDB
- FAISS
- Pinecone (extensible)

### Tools and APIs
- Web search
- File operations
- Custom tool integrations

## Best Practices

1. **Always extend BaseAgent** for new agents
2. **Use prompt templates** from `models/prompts`
3. **Configure via environment variables** for secrets
4. **Write tests** for custom agents and utilities
5. **Document your code** with docstrings
6. **Follow the contribution guidelines**

## Development Workflow

1. Create virtual environment
2. Install dependencies: `make install`
3. Implement features
4. Write tests: `make test`
5. Format code: `make format`
6. Lint code: `make lint`
7. Submit PR

## Security Considerations

- Never commit API keys or secrets
- Use `.env` file for local development
- Validate all user inputs
- Follow secure coding practices

## Future Enhancements

- Multi-agent collaboration frameworks
- Advanced RAG implementations
- Tool use and function calling
- Agent orchestration systems
- Performance monitoring and analytics

## Resources

- [OpenAI API](https://platform.openai.com/docs)
- [LangChain](https://python.langchain.com/)
- [AutoGen](https://microsoft.github.io/autogen/)
