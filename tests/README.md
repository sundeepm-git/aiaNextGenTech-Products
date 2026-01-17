# Tests

Test suite for the aiaNextGenTech-Products repository.

## Running Tests

```bash
# Install test dependencies
pip install -r requirements.txt

# Run all tests
pytest

# Run with coverage
pytest --cov=. --cov-report=html

# Run specific test file
pytest tests/test_utils.py

# Run specific test
pytest tests/test_utils.py::test_get_env_var_existing
```

## Current Tests

- `test_utils.py` - Tests for utility functions
- `conftest.py` - Shared pytest fixtures

## Writing Tests

- Follow existing test patterns
- Use descriptive test names
- Include docstrings explaining what's being tested
- Mock external API calls
- Test edge cases and error handling

## Test Coverage

Aim for at least 80% code coverage for new features.

## Future Test Structure

As the project grows, tests will be organized into subdirectories:
- `test_agents/` - Agent tests
- `test_models/` - Model tests
- Additional test modules as needed
