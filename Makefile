.PHONY: server console help deps deps.up deps.down deps.logs deps.status

COMPOSE_FILE := local-dependencies.yaml

deps.up:
	@echo "Starting local dependencies..."
	@docker compose -f $(COMPOSE_FILE) up -d
	@echo "Services starting. Run 'make deps.logs' to follow."

deps.down:
	@docker compose -f $(COMPOSE_FILE) down
	@echo "Local dependencies stopped"

deps.logs:
	@docker compose -f $(COMPOSE_FILE) logs -f

deps.status:
	@docker compose -f $(COMPOSE_FILE) ps

server:
	@echo "🚀 Starting Phoenix server with remote console support..."
	@echo "📝 Server: http://localhost:4000"
	@echo "🔧 Remote console: make console"
	@iex --sname phoenix@localhost -S mix phx.server

console:
	@echo "🔌 Connecting to remote Phoenix console..."
	@echo "💡 Commands: recompile() | System.restart() | Ctrl+C twice to exit"
	@iex --sname console@localhost --remsh phoenix@localhost

help:
	@echo "Phoenix Template Server - Available Commands"
	@echo ""
	@echo "Development:"
	@echo "  make server            - Start Phoenix server with remote console"
	@echo "  make console           - Connect to running Phoenix console"
	@echo ""
	@echo "Local Dependencies (docker compose):"
	@echo "  make deps.up           - Start all local dependencies"
	@echo "  make deps.down         - Stop all local dependencies"
	@echo "  make deps.logs         - Follow dependency logs"
	@echo "  make deps.status       - Show running services"
	@echo ""
	@echo "Usage:"
	@echo "  1. Start services:  make deps.up"
	@echo "  2. Start server:    make server"
	@echo "  3. In another terminal, connect: make console"
