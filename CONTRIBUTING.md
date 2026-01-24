# Contributing to aiaNextGenTech-Products

Thank you for your interest in contributing to our GenAI and AgenticAI products! This document provides guidelines for contributing to the project.

## Code of Conduct

- Be respectful and inclusive
- Welcome newcomers and encourage diverse perspectives
- Focus on constructive feedback

## How to Contribute

### Reporting Issues

- Check if the issue already exists
- Provide clear reproduction steps
- Include relevant logs and error messages
- Specify your environment (OS, Python version, etc.)

### Suggesting Features

- Open an issue with the `enhancement` label
- Clearly describe the feature and its benefits
- Explain use cases

### Submitting Pull Requests

1. **Fork the repository**
2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes**
   - Write clear, documented code
   - Follow existing code style
   - Add tests for new functionality
4. **Test your changes**
   ```bash
   pytest tests/
   ```
5. **Commit your changes**
   ```bash
   git commit -m "Add: brief description of changes"
   ```
6. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```
7. **Open a Pull Request**

## Development Guidelines

### Code Style

- Follow PEP 8 for Python code
- Use meaningful variable and function names
- Add docstrings to functions and classes
- Keep functions focused and concise

### Testing

- Write unit tests for new features
- Ensure all tests pass before submitting PR
- Aim for high code coverage

### Documentation

- Update README.md if adding new features
- Add docstrings to all public functions
- Include examples for complex functionality
- Update relevant documentation in `docs/`

### Commit Messages

Use clear, descriptive commit messages:
- `Add: new feature description`
- `Fix: bug description`
- `Update: changes to existing feature`
- `Docs: documentation updates`
- `Test: test-related changes`

## Project Structure

- `agents/` - AgenticAI implementations
- `models/` - GenAI models and configurations
- `utils/` - Shared utilities
- `examples/` - Usage examples
- `tests/` - Test suites
- `docs/` - Documentation

## Questions?

Feel free to open an issue with your questions or reach out to the maintainers.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
