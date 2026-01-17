# Utilities

Common utilities and helper functions used across the project.

## Contents

- **config**: Configuration management utilities
- **logging**: Logging configuration and utilities

## Usage

```python
from utils.logging import setup_logger
from utils.config import load_config

logger = setup_logger(__name__)
config = load_config('config.yaml')
```

## Future Extensions

Planned utility modules:
- API client wrappers
- Data processing utilities
- Input validation and sanitization
