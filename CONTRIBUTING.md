# Contributing to SnmpKit

Thank you for your interest in contributing to SnmpKit! This document provides guidelines and information for contributors.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Contributing Process](#contributing-process)
- [Code Standards](#code-standards)
- [Testing Guidelines](#testing-guidelines)
- [Documentation](#documentation)
- [Submitting Changes](#submitting-changes)
- [Release Process](#release-process)
- [Getting Help](#getting-help)

## Code of Conduct

This project adheres to a code of conduct that we expect all contributors to follow. Please be respectful, inclusive, and constructive in all interactions.

### Our Standards

- Use welcoming and inclusive language
- Be respectful of differing viewpoints and experiences
- Gracefully accept constructive criticism
- Focus on what is best for the community
- Show empathy towards other community members

## Getting Started

### Prerequisites

- Elixir 1.14+ and OTP 25+
- Git
- A GitHub account
- Basic understanding of SNMP concepts
- Familiarity with Elixir/OTP development

### Types of Contributions

We welcome various types of contributions:

- **Bug Reports** - Help us identify and fix issues
- **Feature Requests** - Suggest new functionality
- **Code Contributions** - Bug fixes, new features, improvements
- **Documentation** - Improve docs, examples, guides
- **Testing** - Add test cases, improve test coverage
- **Performance** - Optimization and benchmarking
- **Device Profiles** - Add support for new device types

## Development Setup

### Clone the Repository

```bash
git clone https://github.com/awksedgreep/snmpkit.git
cd snmpkit
```

### Install Dependencies

```bash
mix deps.get
```

### Verify Setup

```bash
# Run the test suite
mix test

# Generate documentation
mix docs

# Check code formatting
mix format --check-formatted

# Run static analysis
mix credo
```

### Development Tools

We recommend using these tools for development:

- **Editor**: VS Code with ElixirLS extension
- **Formatter**: Built-in `mix format`
- **Linter**: Credo for code analysis
- **Testing**: ExUnit with coverage reporting
- **Docs**: ExDoc for documentation generation

## Contributing Process

### 1. Create an Issue

Before starting work, please create an issue to discuss:

- Bug reports with reproduction steps
- Feature requests with use cases
- Performance improvements with benchmarks
- Documentation improvements

### 2. Fork and Branch

```bash
# Fork the repository on GitHub
# Clone your fork
git clone https://github.com/yourusername/snmpkit.git
cd snmpkit

# Create a feature branch
git checkout -b feature/your-feature-name
```

### 3. Make Changes

- Follow our [code standards](#code-standards)
- Add tests for new functionality
- Update documentation as needed
- Ensure all tests pass

### 4. Test Your Changes

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run integration tests
mix test --include integration

# Run performance tests
mix test --include performance
```

### 5. Submit a Pull Request

- Push your branch to your fork
- Create a pull request with a clear description
- Reference any related issues
- Ensure CI passes

## Code Standards

### Elixir Style Guide

We follow the [Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide) with these specific preferences:

#### Formatting

```elixir
# Use mix format - it's configured in .formatter.exs
mix format
```

#### Naming Conventions

```elixir
# Modules: PascalCase
defmodule SnmpKit.MIB.Resolver do
end

# Functions: snake_case
def resolve_oid(name) do
end

# Variables: snake_case
result_set = []

# Constants: SCREAMING_SNAKE_CASE
@default_timeout 5_000
```

#### Documentation

```elixir
defmodule SnmpKit.Example do
  @moduledoc """
  Brief module description.
  
  Longer description with examples if needed.
  
  ## Examples
  
      iex> SnmpKit.Example.function()
      {:ok, result}
  """
  
  @doc """
  Brief function description.
  
  ## Parameters
  
  - `param1` - Description of parameter
  - `param2` - Description of parameter
  
  ## Returns
  
  - `{:ok, result}` on success
  - `{:error, reason}` on failure
  
  ## Examples
  
      iex> SnmpKit.Example.function("test")
      {:ok, "result"}
  """
  @spec function(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def function(param1) do
    {:ok, param1}
  end
end
```

#### Error Handling

```elixir
# Use tagged tuples for function returns
def get_value(key) do
  case fetch_value(key) do
    {:ok, value} -> {:ok, value}
    {:error, :not_found} -> {:error, :not_found}
    {:error, reason} -> {:error, reason}
  end
end

# Use with statements for complex operations
def complex_operation(data) do
  with {:ok, parsed} <- parse_data(data),
       {:ok, validated} <- validate_data(parsed),
       {:ok, result} <- process_data(validated) do
    {:ok, result}
  else
    {:error, reason} -> {:error, reason}
  end
end
```

#### Pattern Matching

```elixir
# Prefer pattern matching over conditionals
def handle_response({:ok, %{status: 200, body: body}}) do
  process_success(body)
end

def handle_response({:ok, %{status: status}}) when status >= 400 do
  {:error, :http_error}
end

def handle_response({:error, reason}) do
  {:error, reason}
end
```

### Code Organization

#### Module Structure

```elixir
defmodule SnmpKit.Example do
  @moduledoc "..."
  
  # Behaviours
  @behaviour SomeBehaviour
  
  # Use statements
  use GenServer
  
  # Import statements
  import SomeModule
  
  # Alias statements
  alias SnmpKit.Other.Module
  
  # Module attributes
  @default_timeout 5_000
  
  # Types
  @type example_type :: atom() | String.t()
  
  # Public API
  def public_function do
  end
  
  # Private functions
  defp private_function do
  end
end
```

#### File Organization

```
lib/
├── snmpkit.ex              # Main module with convenience functions
├── snmpkit/
│   ├── snmp/               # SNMP operations
│   │   ├── client.ex
│   │   ├── engine.ex
│   │   └── formatter.ex
│   ├── mib/                # MIB management
│   │   ├── resolver.ex
│   │   ├── compiler.ex
│   │   └── loader.ex
│   └── sim/                # Device simulation
│       ├── device.ex
│       └── profile_loader.ex
```

## Testing Guidelines

### Test Organization

```elixir
defmodule SnmpKit.ExampleTest do
  use ExUnit.Case, async: true
  
  alias SnmpKit.Example
  
  describe "function_name/1" do
    test "handles valid input" do
      assert {:ok, result} = Example.function_name("valid")
      assert result == "expected"
    end
    
    test "handles invalid input" do
      assert {:error, :invalid} = Example.function_name("invalid")
    end
    
    test "handles edge cases" do
      assert {:ok, ""} = Example.function_name("")
      assert {:error, :invalid} = Example.function_name(nil)
    end
  end
end
```

### Test Categories

Use tags to categorize tests:

```elixir
@moduletag :unit           # Fast unit tests
@moduletag :integration    # Tests with external dependencies
@moduletag :performance    # Performance benchmarks
@moduletag :docsis         # DOCSIS-specific tests
```

### Test Data

- Use ExUnit setup for test data
- Create realistic test fixtures
- Use property-based testing for complex scenarios

```elixir
defmodule SnmpKit.PropertyTest do
  use ExUnit.Case
  use PropCheck
  
  property "OID resolution is consistent" do
    forall oid <- valid_oid() do
      case SnmpKit.MIB.resolve(oid) do
        {:ok, resolved} -> is_list(resolved)
        {:error, _} -> true
      end
    end
  end
end
```

### Coverage Requirements

- Maintain >95% test coverage
- Test both success and error paths
- Include edge cases and boundary conditions
- Test concurrent operations where applicable

## Documentation

### Code Documentation

- All public modules must have `@moduledoc`
- All public functions must have `@doc`
- Include `@spec` for all public functions
- Provide examples in doctests

### Guides and Tutorials

- Update relevant guides when adding features
- Include practical examples
- Explain the "why" not just the "how"
- Keep examples up to date

### API Documentation

- Use clear, concise language
- Include parameter descriptions
- Document return values and error conditions
- Provide usage examples

## Submitting Changes

### Pull Request Guidelines

#### Title Format

Use conventional commit format:

- `feat: add new SNMP operation`
- `fix: resolve OID resolution bug`
- `docs: update MIB guide`
- `test: add performance benchmarks`
- `refactor: improve error handling`

#### Description Template

```markdown
## Summary
Brief description of changes

## Changes
- List of specific changes
- Include any breaking changes

## Testing
- How the changes were tested
- New test cases added

## Documentation
- Documentation updates made
- Examples added/updated

## Related Issues
Fixes #123
Closes #456
```

#### Checklist

Before submitting, ensure:

- [ ] Code follows style guidelines
- [ ] Tests pass locally
- [ ] New tests added for new functionality
- [ ] Documentation updated
- [ ] No breaking changes (or clearly marked)
- [ ] Commit messages follow conventional format
- [ ] Branch is up to date with main

### Review Process

1. **Automated Checks** - CI runs tests and checks
2. **Code Review** - Maintainers review code
3. **Discussion** - Address any feedback
4. **Approval** - At least one maintainer approval
5. **Merge** - Squash and merge to main

### After Your PR is Merged

- Delete your feature branch
- Update your fork's main branch
- Consider contributing more!

## Release Process

### Versioning

We follow [Semantic Versioning](https://semver.org/):

- **MAJOR** - Breaking changes
- **MINOR** - New features, backward compatible
- **PATCH** - Bug fixes, backward compatible

### Release Workflow

1. Update version in `mix.exs`
2. Update `CHANGELOG.md`
3. Create release PR
4. Tag release after merge
5. Publish to Hex.pm
6. Update documentation

## Getting Help

### Communication Channels

- **GitHub Issues** - Bug reports, feature requests
- **GitHub Discussions** - General questions, ideas
- **Email** - Security issues only

### Documentation Resources

- [API Documentation](https://hexdocs.pm/snmpkit)
- [MIB Guide](docs/mib-guide.md)
- [Testing Guide](docs/testing-guide.md)
- [Examples](https://github.com/awksedgreep/snmpkit/tree/main/examples)

### Mentorship

New contributors are welcome! We're happy to help you get started:

- Look for "good first issue" labels
- Ask questions in discussions
- Start with documentation improvements
- Join our community

## Recognition

Contributors are recognized in:

- CHANGELOG.md for each release
- README.md contributors section
- GitHub contributors graph
- Special recognition for significant contributions

Thank you for contributing to SnmpKit! Your efforts help make SNMP management better for everyone in the Elixir community.