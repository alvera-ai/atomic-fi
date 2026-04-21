.PHONY: server console help run-backing-services stop-backing-services deps.logs deps.status run-watchman stop-watchman

COMPOSE_FILE := local-dependencies.yaml

run-backing-services:
	@echo "Starting local backing services..."
	@docker compose -f $(COMPOSE_FILE) up -d
	@$(MAKE) run-watchman
	@echo "Backing services ready. Run 'make deps.logs' to follow."

stop-backing-services:
	@echo "Stopping local backing services..."
	@docker compose -f $(COMPOSE_FILE) down
	@$(MAKE) stop-watchman
	@echo "Backing services stopped."

deps.logs:
	@docker compose -f $(COMPOSE_FILE) logs -f

deps.status:
	@docker compose -f $(COMPOSE_FILE) ps

WATCHMAN_IMAGE := moov/watchman:v0.61.1
WATCHMAN_CONFIG := $(CURDIR)/config.all-lists.yml
WATCHMAN_DATA := $(CURDIR)/custom-watchlist.jsonl

run-watchman:
	@echo "Starting Watchman sanctions screening service..."
	@docker run -d \
		--name watchman-local \
		-p 8084:8084 \
		-p 9094:9094 \
		-v $(WATCHMAN_CONFIG):/app/config.yml \
		-v $(WATCHMAN_DATA):/data/custom_watchlist.jsonl \
		-e APP_CONFIG=/app/config.yml \
		$(WATCHMAN_IMAGE)
	@echo "Watchman ready on http://localhost:8084"

stop-watchman:
	@echo "Stopping Watchman..."
	@docker rm -f watchman-local
	@echo "Watchman stopped."

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
	@echo "  make run-backing-services    - Start all services (Docker Compose + Watchman)"
	@echo "  make stop-backing-services   - Stop all services"
	@echo "  make deps.logs               - Follow Docker Compose logs"
	@echo "  make deps.status             - Show running Docker Compose services"
	@echo ""
	@echo "Watchman (Sanctions Screening):"
	@echo "  make run-watchman            - Start Watchman standalone"
	@echo "  make stop-watchman           - Stop Watchman"
	@echo ""
	@echo "Usage:"
	@echo "  1. Start services:  make run-backing-services"
	@echo "  2. Start server:    make server"
	@echo "  3. In another terminal, connect: make console"
