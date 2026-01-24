# Examples

Sample implementations and usage patterns for GenAI and AgenticAI products.

## Available Examples

- `simple_agent.py` - Basic agent template with dotenv
- `base_agent_example.py` - Demonstrates extending BaseAgent class

Examples demonstrate:
- Basic agent creation and usage
- Extending the BaseAgent class
- Agent conversation history management
- Proper agent architecture patterns

## Running Examples

### Option 1: Using PYTHONPATH (Quick)
```bash
# Set PYTHONPATH to project root
export PYTHONPATH="${PYTHONPATH}:$(pwd)"

# Run an example
python examples/base_agent_example.py
```

### Option 2: Install in Development Mode (Recommended)
```bash
# Activate virtual environment
source venv/bin/activate

# Install package in development mode
pip install -e .

# Run an example
python examples/base_agent_example.py
```

### Option 3: With Dependencies
```bash
# For examples that use external APIs
cp .env.example .env
# Edit .env with your API keys

# Run example
python examples/simple_agent.py
```

## Contributing Examples

When adding new examples:
1. Include clear comments explaining the code
2. Add a README or docstring describing what the example demonstrates
3. Ensure all dependencies are listed in requirements.txt
4. Test the example thoroughly before submitting
