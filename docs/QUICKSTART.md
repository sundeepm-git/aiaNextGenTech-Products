# Quick Start Guide

This guide will help you get started with the aiaNextGenTech-Products repository.

## Prerequisites

- Python 3.8 or higher
- pip (Python package manager)
- Git

## Installation Steps

### 1. Clone the Repository

```bash
git clone https://github.com/sundeepm-git/aiaNextGenTech-Products.git
cd aiaNextGenTech-Products
```

### 2. Create a Virtual Environment

**On Linux/Mac:**
```bash
python -m venv venv
source venv/bin/activate
```

**On Windows:**
```bash
python -m venv venv
venv\Scripts\activate
```

### 3. Install Dependencies

```bash
pip install -r requirements.txt
```

Or use the Makefile:
```bash
make install
```

### 4. Set Up Environment Variables

Copy the example environment file and add your API keys:

```bash
cp .env.example .env
```

Edit `.env` and add your API keys:
```
OPENAI_API_KEY=your_actual_key_here
```

## Running Your First Example

Try running the simple agent example:

```bash
python examples/simple_agent.py
```

Or use the Makefile:
```bash
make run-example
```

## Project Structure Overview

- **agents/**: Create autonomous agents here
- **models/**: GenAI models and prompt configurations
- **utils/**: Common utilities (logging, config, etc.)
- **examples/**: Sample code and tutorials
- **tests/**: Test files
- **configs/**: Configuration files

## Next Steps

### Explore Examples

Check the `examples/` directory for more sample implementations.

### Create Your Own Agent

Use `examples/simple_agent.py` as a template to create your own AI agent.

### Add Your Own Code

1. Create agent implementations in `agents/`
2. Add model configurations in `models/`
3. Use utilities from `utils/` for common tasks
4. Write tests in `tests/`

### Run Tests

```bash
pytest tests/ -v
```

Or use the Makefile:
```bash
make test
```

## Common Commands

```bash
# Install dependencies
make install

# Run tests
make test

# Format code
make format

# Lint code
make lint

# Clean temporary files
make clean
```

## Getting Help

- Read the [README.md](README.md) for detailed information
- Check [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines
- Open an issue on GitHub for questions or bug reports

## Additional Resources

- [OpenAI API Documentation](https://platform.openai.com/docs)
- [LangChain Documentation](https://python.langchain.com/)
- [Python Virtual Environments](https://docs.python.org/3/tutorial/venv.html)
