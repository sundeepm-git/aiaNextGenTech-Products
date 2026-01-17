# Utilities

Common utilities and helper functions used across the project.

## Contents

- **logging**: Logging configuration and utilities
- **api_clients**: API client wrappers
- **data_processing**: Data handling and processing utilities
- **config**: Configuration management
- **validation**: Input validation and sanitization

## Usage

```python
from utils.logging import setup_logger
from utils.config import load_config

logger = setup_logger(__name__)
config = load_config('config.yaml')
```
