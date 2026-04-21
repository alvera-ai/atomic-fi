.PHONY: server console help run-backing-services stop-backing-services deps.logs deps.status

COMPOSE_FILE := local-dependencies.yaml

run-backing-services:
	@echo "Starting local backing services..."
	@docker compose -f $(COMPOSE_FILE) up -d
	@echo "Backing services ready. Run 'make deps.logs' to follow."

stop-backing-services:
	@echo "Stopping local backing services..."
	@docker compose -f $(COMPOSE_FILE) down
	@echo "Backing services stopped."

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
	@echo "Payments Compliance Platform - Available Commands"
	@echo ""
	@echo "Development:"
	@echo "  make server                  - Start Phoenix server with remote console"
	@echo "  make console                 - Connect to running Phoenix console"
	@echo ""
	@echo "Backing Services (Docker):"
	@echo "  make run-backing-services    - Start local Docker services"
	@echo "  make stop-backing-services   - Stop local Docker services"
	@echo "  make deps.logs               - Follow service logs"
	@echo "  make deps.status             - Show running services"
	@echo ""
	@echo "Usage:"
	@echo "  1. Start services:  make run-backing-services"
	@echo "  2. Start server:    make server"
	@echo "  3. In another terminal, connect: make console"
