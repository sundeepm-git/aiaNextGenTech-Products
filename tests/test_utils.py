"""
Tests for utility functions.
"""

import os
import pytest
from utils.config import get_env_var, validate_api_keys


def test_get_env_var_existing(monkeypatch):
    """Test getting an existing environment variable."""
    monkeypatch.setenv("TEST_VAR", "test_value")
    assert get_env_var("TEST_VAR") == "test_value"


def test_get_env_var_default():
    """Test getting a non-existing variable with default."""
    result = get_env_var("NON_EXISTENT_VAR", "default_value")
    assert result == "default_value"


def test_get_env_var_none():
    """Test getting a non-existing variable without default."""
    result = get_env_var("NON_EXISTENT_VAR")
    assert result is None


def test_validate_api_keys_with_key(monkeypatch):
    """Test API key validation with key present."""
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    assert validate_api_keys() is True


def test_validate_api_keys_without_key(monkeypatch):
    """Test API key validation without key."""
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    assert validate_api_keys() is False
