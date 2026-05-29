.PHONY: server console help run-backing-services stop-backing-services deps.logs deps.status run-watchman stop-watchman up down seed test-integration test-playwright sight ai-doc.server ai-doc.check ai-doc.install reseed-stableaml reseed-saml-d reseed-amlgentex bench hydrate-zen-rules test-bruno test-corpus

COMPOSE_FILE := local-dependencies.yaml

# ─── Synthetic corpus upstreams ─────────────────────────────────────────
#
# Raw upstream datasets live OUTSIDE the repo, under CORPUS_OUT (default
# CORPUS_ROOT, default ~/.local/share/atomic-fi/corpus). Each
# `reseed-<src>` target is idempotent and produces a CANONICAL,
# already-subsetted artefact that `mix corpus.generate.<src>` reads —
# usually an NDJSON file so Elixir does no CSV/Parquet parsing. For huge
# upstreams (SAML-D 12 MB, AMLGentex GB-scale parquet) the Python
# subset step happens inside this Makefile target, NOT inside Elixir.
#
# sha256 against the committed manifest at
# `corpus/upstream/<src>/manifest.json` is the contract for ingestion.
# Re-running with the file already present and matching sha is a no-op.
#
# CORPUS_OUT (per-invocation) > ATOMIC_FI_CORPUS_OUT (env) > CORPUS_ROOT
# (legacy) > ATOMIC_FI_CORPUS_ROOT (env) > $HOME/.local/share/atomic-fi/corpus.
#
# These targets are curl + gunzip / unzip + python — native, no docker.
# Docker enters the picture only for backing services (Watchman,
# ZenRule), never for plumbing tasks like this.

CORPUS_OUT ?= $(or $(ATOMIC_FI_CORPUS_OUT),$(CORPUS_ROOT),$(ATOMIC_FI_CORPUS_ROOT),$(HOME)/.local/share/atomic-fi/corpus)

# ─── StableAML — Category-1 sanctioned wallet CSV (~53 kB) ────────────
STABLEAML_MANIFEST := $(CURDIR)/corpus/upstream/stableaml/manifest.json
STABLEAML_DIR := $(CORPUS_OUT)/stableaml
STABLEAML_GZ := $(STABLEAML_DIR)/address_sanctioned.csv.gz
STABLEAML_CSV := $(STABLEAML_DIR)/address_sanctioned.csv
STABLEAML_GZ_URL := https://raw.githubusercontent.com/finos-labs/dtcch-2025-OpenAML/main/Data/address_sanctioned.csv.gz
STABLEAML_GZ_SHA256 := de596bc4287d9f09365d20df4c4a73bfcc78526ff3675e68fe25090a02240968
STABLEAML_CSV_SHA256 := 89cfc6ea2263ce9b1c39c5a4a907c51b7968ac4e2563a42d0d65fa0d5bb3ea09

reseed-stableaml:
	@set -e; \
	echo "→ reseed-stableaml: CORPUS_OUT=$(CORPUS_OUT)"; \
	mkdir -p "$(STABLEAML_DIR)"; \
	if [ -f "$(STABLEAML_CSV)" ] && [ "$$(shasum -a 256 '$(STABLEAML_CSV)' | awk '{print $$1}')" = "$(STABLEAML_CSV_SHA256)" ]; then \
		echo "✓ $(STABLEAML_CSV) already present, sha256 matches — no-op"; \
		exit 0; \
	fi; \
	echo "→ curling $(STABLEAML_GZ_URL)"; \
	curl -fsSL "$(STABLEAML_GZ_URL)" -o "$(STABLEAML_GZ)"; \
	actual=$$(shasum -a 256 "$(STABLEAML_GZ)" | awk '{print $$1}'); \
	if [ "$$actual" != "$(STABLEAML_GZ_SHA256)" ]; then \
		echo "✗ sha256 mismatch on .gz" >&2; \
		echo "  expected: $(STABLEAML_GZ_SHA256)" >&2; \
		echo "  actual:   $$actual" >&2; \
		echo "  manifest: $(STABLEAML_MANIFEST)" >&2; \
		rm -f "$(STABLEAML_GZ)"; \
		exit 1; \
	fi; \
	gunzip -f "$(STABLEAML_GZ)"; \
	actual=$$(shasum -a 256 "$(STABLEAML_CSV)" | awk '{print $$1}'); \
	if [ "$$actual" != "$(STABLEAML_CSV_SHA256)" ]; then \
		echo "✗ sha256 mismatch on .csv" >&2; \
		echo "  expected: $(STABLEAML_CSV_SHA256)" >&2; \
		echo "  actual:   $$actual" >&2; \
		rm -f "$(STABLEAML_CSV)"; \
		exit 1; \
	fi; \
	echo "✓ StableAML ingested to $(STABLEAML_CSV)"

# ─── SAML-D — Kaggle synthetic AML CSV (~12 MB raw → subset NDJSON) ────
SAML_D_MANIFEST := $(CURDIR)/corpus/upstream/saml-d/manifest.json
SAML_D_DIR := $(CORPUS_OUT)/saml-d
SAML_D_RAW_CSV := $(SAML_D_DIR)/SAML-D.csv
SAML_D_NDJSON := $(SAML_D_DIR)/saml_d.ndjson
SAML_D_KAGGLE_DATASET := berkanoztas/synthetic-transaction-monitoring-dataset-aml
# RNG seed for the Python subset step; deterministic across reseeds.
SAML_D_SEED ?= 0
# Default subset size; override on the command line for larger runs.
SAML_D_ROWS ?= 1000

reseed-saml-d:
	@set -e; \
	echo "→ reseed-saml-d: CORPUS_OUT=$(CORPUS_OUT)  rows=$(SAML_D_ROWS)  seed=$(SAML_D_SEED)"; \
	mkdir -p "$(SAML_D_DIR)"; \
	command -v kaggle >/dev/null 2>&1 || { \
		echo "✗ kaggle CLI not found on PATH." >&2; \
		echo "   Install: pip install kaggle  (or: pipx install kaggle)" >&2; \
		echo "   Auth:    https://www.kaggle.com/settings  →  Create New Token" >&2; \
		echo "            move kaggle.json to ~/.kaggle/  (chmod 600)" >&2; \
		exit 1; \
	}; \
	command -v python3 >/dev/null 2>&1 || { \
		echo "✗ python3 not found on PATH (needed for the subset step)" >&2; \
		exit 1; \
	}; \
	if [ ! -f "$(SAML_D_RAW_CSV)" ]; then \
		echo "→ kaggle datasets download $(SAML_D_KAGGLE_DATASET) → $(SAML_D_DIR)"; \
		kaggle datasets download -d $(SAML_D_KAGGLE_DATASET) -p "$(SAML_D_DIR)" --unzip; \
	else \
		echo "✓ $(SAML_D_RAW_CSV) already present"; \
	fi; \
	if [ ! -f "$(SAML_D_RAW_CSV)" ]; then \
		echo "✗ kaggle download did not produce $(SAML_D_RAW_CSV)" >&2; \
		echo "   Inspect: ls $(SAML_D_DIR)" >&2; \
		exit 1; \
	fi; \
	echo "→ python3 subset: $(SAML_D_ROWS) rows, seed=$(SAML_D_SEED)"; \
	python3 -c "import pandas as pd; \
df = pd.read_csv('$(SAML_D_RAW_CSV)'); \
df.sample(n=min($(SAML_D_ROWS), len(df)), random_state=$(SAML_D_SEED)) \
  .to_json('$(SAML_D_NDJSON)', orient='records', lines=True)"; \
	echo "✓ SAML-D subset written to $(SAML_D_NDJSON)  ($$(wc -l < $(SAML_D_NDJSON)) rows)"

# ─── AMLGentex — Python sim → parquet → subset NDJSON ──────────────────
AMLGENTEX_MANIFEST := $(CURDIR)/corpus/upstream/amlgentex/manifest.json
AMLGENTEX_CONF := $(CURDIR)/corpus/upstream/amlgentex/config/data.yaml
AMLGENTEX_DIR := $(CORPUS_OUT)/amlgentex
AMLGENTEX_REPO := $(AMLGENTEX_DIR)/repo
AMLGENTEX_REF ?= main
AMLGENTEX_PARQUET := $(AMLGENTEX_DIR)/transactions.parquet
AMLGENTEX_NDJSON := $(AMLGENTEX_DIR)/amlgentex.ndjson
AMLGENTEX_SEED ?= 0
AMLGENTEX_ROWS ?= 1000

reseed-amlgentex:
	@set -e; \
	echo "→ reseed-amlgentex: CORPUS_OUT=$(CORPUS_OUT)  rows=$(AMLGENTEX_ROWS)  seed=$(AMLGENTEX_SEED)"; \
	mkdir -p "$(AMLGENTEX_DIR)"; \
	command -v git    >/dev/null 2>&1 || { echo "✗ git not found"   >&2; exit 1; }; \
	command -v python3 >/dev/null 2>&1 || { echo "✗ python3 not found" >&2; exit 1; }; \
	command -v uv     >/dev/null 2>&1 || { \
		echo "✗ uv not found on PATH." >&2; \
		echo "   Install: pipx install uv  (or: pip install uv)" >&2; \
		exit 1; \
	}; \
	if [ ! -d "$(AMLGENTEX_REPO)/.git" ]; then \
		echo "→ git clone aidotse/AMLGentex ($(AMLGENTEX_REF)) → $(AMLGENTEX_REPO)"; \
		git clone --depth 1 --branch $(AMLGENTEX_REF) https://github.com/aidotse/AMLGentex.git "$(AMLGENTEX_REPO)"; \
	else \
		echo "→ pull AMLGentex repo (ref=$(AMLGENTEX_REF))"; \
		git -C "$(AMLGENTEX_REPO)" fetch --depth 1 origin $(AMLGENTEX_REF); \
		git -C "$(AMLGENTEX_REPO)" checkout $(AMLGENTEX_REF); \
	fi; \
	echo "→ uv sync (Python deps for AMLGentex)"; \
	cd "$(AMLGENTEX_REPO)" && uv sync >/dev/null; \
	echo "→ uv run scripts/generate.py --conf_file $(AMLGENTEX_CONF)"; \
	cd "$(AMLGENTEX_REPO)" && uv run python scripts/generate.py --conf_file "$(AMLGENTEX_CONF)" --output_path "$(AMLGENTEX_PARQUET)"; \
	if [ ! -f "$(AMLGENTEX_PARQUET)" ]; then \
		echo "✗ AMLGentex sim did not produce $(AMLGENTEX_PARQUET)" >&2; \
		exit 1; \
	fi; \
	echo "→ python3 subset (polars): $(AMLGENTEX_ROWS) rows, seed=$(AMLGENTEX_SEED)"; \
	python3 -c "import polars as pl; \
df = pl.read_parquet('$(AMLGENTEX_PARQUET)'); \
df.sample(n=min($(AMLGENTEX_ROWS), df.height), seed=$(AMLGENTEX_SEED)) \
  .write_ndjson('$(AMLGENTEX_NDJSON)')"; \
	echo "✓ AMLGentex subset written to $(AMLGENTEX_NDJSON)  ($$(wc -l < $(AMLGENTEX_NDJSON)) rows)"

# Hydrate ZenRule's runtime rules dir from /zen_rules/ (the committed
# source of truth) into /priv/zenrule/ (gitignored, bind-mounted into the
# gorules/agent container). Same pattern as the Vite-built SPAs:
# committed source → throwaway runtime location.
#
# Clean sync: wipes the demo subdirs first so leftover artifacts from a
# previous JDM-editor session (interrupted Playwright runs that called
# `save_rule` leave throwaway files behind, and the gorules/agent loader
# happily picks them up + fails to evaluate them, breaking the test suite
# on the next run). The test-fixtures-* sibling directories are untouched.
hydrate-zen-rules:
	@echo "Hydrating priv/zenrule/{onboarding,transaction-screening}/ from zen_rules/ ..."
	@rm -rf priv/zenrule/onboarding priv/zenrule/transaction-screening
	@mkdir -p priv/zenrule/onboarding priv/zenrule/transaction-screening
	@cp zen_rules/onboarding/*.json priv/zenrule/onboarding/
	@cp zen_rules/transaction-screening/*.json priv/zenrule/transaction-screening/
	@echo "✓ ZenRule rules hydrated."

run-backing-services: hydrate-zen-rules
	@echo "Starting local backing services (docker compose: watchman)..."
	@docker compose -f $(COMPOSE_FILE) up -d --build
	@echo "Backing services ready. Run 'make deps.logs' to follow."
	@echo "Note: compose-managed watchman uses upstream moov/watchman with the"
	@echo "      same config + custom watchlist as 'make run-watchman'."
	@echo "      The standalone target remains available for running watchman"
	@echo "      outside compose (e.g. on a host without docker compose)."

# ─── corpus.bench — k6-shape VU-sweep performance cert ─────────────────
#
# Each VU is one parallel iteration of one of the 10 catalog scenarios
# (round-robin) under corpus/zen_rules/<slug>/. Within a VU the txns run
# sequentially (velocity rules); across VUs the runs are independent
# (UUID id-prefix per VU). Writes one committed GitHub-flavored
# markdown report under benchmarks/.
#
#   make bench
#   make bench BENCH_LEVELS=1,10,100,1000
#
# Bump POOL_SIZE for the larger VU steps — the default of 10 will
# bottleneck at 100+ VUs:
#
#   POOL_SIZE=200 make bench BENCH_LEVELS=1,10,100,1000,2000
#
BENCH_LEVELS ?= 1,10,100,1000,2000,10000
# Unset by default — `mix corpus.bench` auto-derives a meaningful
# filename: benchmarks/<cpu-slug>-<date>-<peak-vus-english>-vus.md
# Set BENCH_REPORT=path/to/file.md to override.
BENCH_REPORT ?=

bench:
	@mix corpus.bench \
		--levels $(BENCH_LEVELS) \
		$(if $(BENCH_REPORT),--report $(BENCH_REPORT))

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
	@echo "✅ Stack ready. Run 'make server' — Phoenix + example-app build watchers run together."

down: stop-backing-services

seed:
	@echo "🌱 Seeding atomic-fi from compliance corpus..."
	@if [ ! -d priv/corpus/out ] || [ -z "$$(ls -A priv/corpus/out 2>/dev/null)" ]; then \
		echo "  → no corpus found, generating default (--shards 100 --pass-rate 90)"; \
		mix alvera.gen.compliance_corpus --shards 100 --pass-rate 90; \
	fi
	@mix bench.seed

test-integration:
	@echo "🧪 Running vitest integration suite..."
	@cd integration-tests && pnpm test

test-playwright:
	@echo "🎭 Running playwright e2e suite..."
	@cd playwright-e2e && pnpm test

# ─── Correctness verification (issue #53) ──────────────────────────────

BRUNO_DIR := bruno/atomic-fi-scenarios
BRUNO_SCENARIOS := $(filter-out environments smoke-tests %.md %.json %.bru,$(notdir $(patsubst %/,%,$(wildcard $(BRUNO_DIR)/*/))))

test-bruno:
	@echo "→ Running Bruno scenarios against live API..."
	@failed=0; total=0; \
	for scenario in $(BRUNO_SCENARIOS); do \
		total=$$((total + 1)); \
		echo "  [$${total}] $$scenario"; \
		if npx @usebruno/cli run "$(BRUNO_DIR)/$$scenario" --env local 2>&1 | tail -1 | grep -q "Failed"; then \
			echo "    ✗ FAILED"; \
			failed=$$((failed + 1)); \
		else \
			echo "    ✓ pass"; \
		fi; \
	done; \
	echo ""; \
	echo "Bruno: $$((total - failed))/$$total scenarios green"; \
	[ $$failed -eq 0 ]

test-corpus:
	@echo "→ Running corpus.validate against all scenarios..."
	@mix corpus.validate --reset

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
	@echo "One-shot:"
	@echo "  make up                      - Backing services + db + seed (then run 'make server')"
	@echo "  make down                    - Stop backing services"
	@echo "  make seed                    - (Re)seed db from priv/corpus/out, generating corpus if missing"
	@echo "  make test-integration        - Run vitest integration suite"
	@echo "  make test-playwright         - Run playwright e2e suite"
	@echo "  make test-bruno              - Run all Bruno scenarios (needs live API)"
	@echo "  make test-corpus             - Run corpus.validate on all scenarios"
	@echo ""
	@echo "Usage:"
	@echo "  1. Start services:  make run-backing-services"
	@echo "  2. Start server:    make server"
	@echo "  3. In another terminal, connect: make console"
