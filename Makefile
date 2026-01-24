# Makefile for aiaNextGenTech-Products

.PHONY: help install install-dev test lint format clean run-example

help:
	@echo "Available commands:"
	@echo "  make install       - Install project dependencies"
	@echo "  make install-dev   - Install project with development dependencies"
	@echo "  make test          - Run tests"
	@echo "  make lint          - Run code linting"
	@echo "  make format        - Format code with black"
	@echo "  make clean         - Clean temporary files"
	@echo "  make run-example   - Run simple agent example"

install:
	pip install -r requirements.txt

install-dev:
	pip install -r requirements.txt
	pip install -e .

test:
	pytest tests/ -v

lint:
	flake8 agents/ models/ utils/ examples/ tests/
	mypy agents/ models/ utils/ examples/

format:
	black agents/ models/ utils/ examples/ tests/

clean:
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
	find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	rm -rf .pytest_cache/ .coverage htmlcov/ build/ dist/

run-example:
	python examples/simple_agent.py
