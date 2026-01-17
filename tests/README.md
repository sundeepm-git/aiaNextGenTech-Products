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
pytest tests/test_agents.py

# Run specific test
pytest tests/test_agents.py::test_agent_initialization
```

## Test Structure

```
tests/
├── test_agents/      # Agent tests
├── test_models/      # Model tests
├── test_utils/       # Utility tests
├── conftest.py       # Shared fixtures
└── README.md         # This file
```

## Writing Tests

- Follow existing test patterns
- Use descriptive test names
- Include docstrings explaining what's being tested
- Mock external API calls
- Test edge cases and error handling

## Test Coverage

Aim for at least 80% code coverage for new features.
