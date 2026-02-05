# Code Quality Checks

Run comprehensive code quality checks before committing.

## Quick Command

```bash
mix quality
```

This runs all quality checks defined in `mix.exs` aliases.

## Individual Commands

### Format Check

```bash
# Check if code is formatted
mix format --check-formatted

# Auto-format code
mix format
```

### Credo (Static Analysis)

```bash
# Run with strict mode
mix credo --strict

# Focus on specific checks
mix credo --only readability
mix credo --only refactor
```

### Sobelow (Security)

```bash
# Run security analysis
mix sobelow --config

# Skip specific checks
mix sobelow --skip Config.HTTPS
```

### Dialyxir (Type Analysis)

```bash
# Run dialyzer
mix dialyzer

# Build PLT (first time only)
mix dialyzer --plt
```

### Test Coverage

```bash
# Run tests with coverage
mix coveralls

# HTML coverage report
mix coveralls.html

# Check coverage threshold (80%+)
mix coveralls --min-coverage 80
```

## Pre-Commit Checklist

Before every commit:

- [ ] `mix format` - Code is formatted
- [ ] `mix credo --strict` - No credo warnings
- [ ] `mix sobelow --config` - No security issues
- [ ] `mix test` - All tests pass
- [ ] `mix dialyzer` - No type errors (optional, slow)

## CI/CD Integration

GitHub Actions runs these checks automatically:

- **code-quality.yml**: Format, Credo, Sobelow, Dialyxir
- **test.yml**: Tests with coverage
- **integration-tests.yml**: Vitest integration tests

## Common Issues

### Credo Warnings

```elixir
# Avoid pipes with single operation
# Bad
user |> update_user(attrs)

# Good
update_user(user, attrs)
```

### Sobelow Security

```elixir
# Don't use String.to_atom with user input
# Bad
String.to_atom(user_input)

# Good
Map.get(%{valid: :keys}, user_input)
```

### Format Issues

```bash
# Format a specific file
mix format lib/path/to/file.ex

# Check what would be formatted
mix format --check-formatted --dry-run
```

## Configuration Files

- `.formatter.exs` - Formatter configuration
- `.credo.exs` - Credo rules (create if needed)
- `sobelow-conf.exs` - Sobelow config (create if needed)
- `.dialyzer_ignore.exs` - Dialyzer ignores (optional)
