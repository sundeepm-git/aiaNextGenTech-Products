"""
Shared pytest fixtures for tests.
"""

import pytest
from pathlib import Path


@pytest.fixture
def project_root():
    """Return the project root directory."""
    return Path(__file__).parent.parent


@pytest.fixture
def sample_config():
    """Return a sample configuration dictionary."""
    return {
        "model": {
            "provider": "openai",
            "name": "gpt-4",
            "temperature": 0.7
        },
        "agent": {
            "timeout": 300,
            "max_retries": 3
        }
    }


@pytest.fixture
def mock_api_key(monkeypatch):
    """Mock API key for testing."""
    monkeypatch.setenv("OPENAI_API_KEY", "test-key-12345")
