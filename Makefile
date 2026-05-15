.PHONY: server console help run-backing-services stop-backing-services deps.logs deps.status run-watchman stop-watchman up down seed test-integration test-playwright sight ai-doc.server ai-doc.check ai-doc.install

COMPOSE_FILE := local-dependencies.yaml

run-backing-services:
	@echo "Starting local backing services (docker compose: watchman)..."
	@docker compose -f $(COMPOSE_FILE) up -d
	@echo "Backing services ready. Run 'make deps.logs' to follow."
	@echo "Note: compose-managed watchman uses upstream moov/watchman with the"
	@echo "      same config + custom watchlist as 'make run-watchman'."
	@echo "      The standalone target remains available for running watchman"
	@echo "      outside compose (e.g. on a host without docker compose)."

stop-backing-services:
	@echo "Stopping local backing services (docker compose)..."
	@docker compose -f $(COMPOSE_FILE) down
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
	@docker run --rm  \
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
	@echo "📝 Server: http://localhost:4100"
	@echo "🔧 Remote console: make console"
	@iex --sname phoenix@localhost -S mix phx.server

console:
	@echo "🔌 Connecting to remote Phoenix console..."
	@echo "💡 Commands: recompile() | System.restart() | Ctrl+C twice to exit"
	@iex --sname console@localhost --remsh phoenix@localhost

up: run-backing-services
	@echo "🛠  Setting up database..."
	@mix ecto.setup
	@$(MAKE) seed
	@echo "✅ Stack ready. Run 'make server' (atomic-fi API) and 'make sight' (atomic-sight UI) in separate terminals."

down: stop-backing-services

seed:
	@echo "🌱 Seeding atomic-fi from compliance corpus..."
	@if [ ! -d priv/corpus/out ] || [ -z "$$(ls -A priv/corpus/out 2>/dev/null)" ]; then \
		echo "  → no corpus found, generating default (--shards 100 --pass-rate 90)"; \
		mix alvera.gen.compliance_corpus --shards 100 --pass-rate 90; \
	fi
	@mix bench.seed

sight:
	@echo "🎨 Starting atomic-sight-insight dev server..."
	@cd packages/atomic-sight-insight && pnpm dev

test-integration:
	@echo "🧪 Running vitest integration suite..."
	@cd integration-tests && pnpm test

test-playwright:
	@echo "🎭 Running playwright e2e suite..."
	@cd playwright-e2e && pnpm test

DOC_AGENT_DIR := ../document-agent

ai-doc.install:
	@echo "Installing document-agent dependencies..."
	@$(MAKE) -C $(DOC_AGENT_DIR) install

ai-doc.server:
	@echo "Starting document-agent API server..."
	@$(MAKE) -C $(DOC_AGENT_DIR) server

ai-doc.check:
	@echo "Running document-agent quality suite..."
	@$(MAKE) -C $(DOC_AGENT_DIR) check

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
	@echo "Document Agent (AI Doc Processing):"
	@echo "  make ai-doc.install          - Install document-agent deps"
	@echo "  make ai-doc.server           - Start document-agent API (port 8100)"
	@echo "  make ai-doc.check            - Run full quality suite (lint/types/test/audit)"
	@echo ""
	@echo "One-shot:"
	@echo "  make up                      - Backing services + db + seed (then run 'make server' and 'make sight')"
	@echo "  make down                    - Stop backing services"
	@echo "  make seed                    - (Re)seed db from priv/corpus/out, generating corpus if missing"
	@echo "  make sight                   - Start atomic-sight-insight Vite dev server"
	@echo "  make test-integration        - Run vitest integration suite"
	@echo "  make test-playwright         - Run playwright e2e suite"
	@echo ""
	@echo "Usage:"
	@echo "  1. Start services:  make run-backing-services"
	@echo "  2. Start server:    make server"
	@echo "  3. In another terminal, connect: make console"
