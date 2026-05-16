.PHONY: install server check lint format typecheck test coverage vulture boundaries audit all help

install:
	@uv sync --group dev

server:
	@uv run uvicorn app.main:app --port 8100 --reload

lint:
	@uv run ruff check app/ tests/

format:
	@uv run ruff format app/ tests/

format.check:
	@uv run ruff format --check app/ tests/

typecheck:
	@uv run pyright app/ tests/

test:
	@uv run pytest tests/ -v

coverage:
	@uv run pytest tests/ --cov --cov-report=term-missing

vulture:
	@uv run vulture app/ vulture_whitelist.py --min-confidence 80

boundaries:
	@uv run lint-imports

audit:
	@uv run pip-audit

check: lint format.check typecheck vulture boundaries test
	@echo "All checks passed."

all: install check
	@echo "Install + checks complete."

help:
	@echo "Document Agent - Available Commands"
	@echo ""
	@echo "Setup:"
	@echo "  make install       - Install all dependencies (uv sync)"
	@echo "  make all           - Install + run all checks"
	@echo ""
	@echo "Development:"
	@echo "  make server        - Start API server (port 8100, hot reload)"
	@echo ""
	@echo "Quality (individual):"
	@echo "  make lint          - Ruff linter (strict)"
	@echo "  make format        - Ruff auto-format"
	@echo "  make format.check  - Check formatting (no changes)"
	@echo "  make typecheck     - Pyright strict type checking"
	@echo "  make test          - Run pytest"
	@echo "  make coverage      - Run pytest with coverage report"
	@echo "  make vulture       - Dead code detection"
	@echo "  make boundaries    - Import boundary enforcement"
	@echo "  make audit         - Dependency vulnerability scan"
	@echo ""
	@echo "Quality (all-in-one):"
	@echo "  make check         - Run entire quality suite"
