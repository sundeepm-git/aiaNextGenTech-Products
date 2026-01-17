# Configuration Files

Configuration files for different environments and services.

## Files

- `config.example.yaml` - Example configuration file
- `development.yaml` - Development environment settings
- `production.yaml` - Production environment settings

## Environment Variables

Create a `.env` file in the root directory with:

```
# API Keys
OPENAI_API_KEY=your_openai_key_here
ANTHROPIC_API_KEY=your_anthropic_key_here

# Model Settings
DEFAULT_MODEL=gpt-4
MAX_TOKENS=2000
TEMPERATURE=0.7

# Agent Settings
AGENT_TIMEOUT=300
MAX_RETRIES=3

# Logging
LOG_LEVEL=INFO
```

## Usage

```python
from utils.config import load_config

config = load_config('configs/development.yaml')
```
