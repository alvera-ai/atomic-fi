# Onboarding Flow

Business onboarding example app — upload documents, AI-extract data, fill the KYB form, and submit to the Atomic FI backend.

## Architecture

```
                                     Gemini 2.5 Flash
                                          |
User → React App (:8080) → Document Agent Server (:8100) → structured JSON → prefill form
                   |
                   └→ Atomic FI Backend (:4100) → AccountHolder + LegalEntity + KYC
```

Three services work together:

| Service | Port | Purpose |
|---------|------|---------|
| **Atomic FI** (Elixir/Phoenix) | 4100 | Backend API — AccountHolder, LegalEntity, KYC, Documents |
| **Document Agent** (Python/FastAPI) | 8100 | AI document extraction via Gemini multimodal |
| **Onboarding Flow** (React/Vite) | 8080 | Frontend — document upload, form wizard, submission |

## Prerequisites

- Elixir 1.18+ / OTP 27+
- Python 3.12+ with [uv](https://docs.astral.sh/uv/)
- Node.js 20+ with [pnpm](https://pnpm.io/)
- Docker Desktop (for Watchman + ZenRule)
- Google API key (for Gemini document extraction)

## Quick Start

### 1. Start backing services (Docker)

From the repo root:

```bash
docker compose -f local-dependencies.yaml up -d
```

This starts:
- **Watchman** (sanctions screening) on port 8084
- **ZenRule** (decision engine) on port 8090

### 2. Start the Elixir backend

```bash
# From repo root
mix setup                    # deps, compile, DB create + migrate + seed
mix phx.server               # starts on :4100
```

First-time setup also needs bootstrap credentials:

```bash
mix atomic_fi.dump_bootstrap_creds
# outputs priv/repo/.bootstrap_creds.json with API keys + tenant info
```

Initialize the blocklist cache (required for onboarding screening):

```bash
# Get a session token
curl -s -X POST http://localhost:4100/api/sessions \
  -H 'content-type: application/json' \
  -d '{"email":"<admin_email>","password":"<admin_password>","tenant_slug":"<slug>","expires_in":3600}' \
  | jq -r '.bearer'

# Refresh blocklist cache
curl -X POST http://localhost:4100/api/tenants/refresh-blocklist-cache \
  -H "authorization: Bearer <token>"
```

### 3. Start the React app

The Python document-agent-server is gone — document extraction now lives
inside Phoenix at `POST /api/parse`, backed by a local Ollama vision
model (no API keys). `make server` starts it alongside everything else.
Confirm Ollama is running with the vision model pulled:

```bash
ollama list | grep llama3.2-vision     # should appear
# If missing: ollama pull llama3.2-vision:11b
```

### 4. Start the React app

```bash
cd example-apps/onboarding-flow

# Configure backend connection
cp .env.example .env.local
# Edit .env.local:
#   VITE_API_KEY=<rootApiKey from bootstrap_creds>
#   VITE_TENANT_ID=<tenant UUID from bootstrap_creds or DB>

# Install deps and start
pnpm install
pnpm dev       # starts on :8080
```

Open http://localhost:8080 in your browser.

## Usage

### Upload & Prefill (AI extraction)

1. Click **"Manual entry"** → **"Start Application"**
2. On the documents page, drag & drop PDFs (MOA, bank statement, passport, etc.)
3. Click **"Process files"** — documents are sent to the Document Agent for AI extraction
4. Extracted data auto-fills: business identity, directors, UBOs, addresses, business activity, transfer behavior
5. Review prefilled steps, adjust if needed, submit

### Manual entry

1. Click **"Manual entry"** → **"Start Application"**
2. Click **"Load all sample files"** for demo data, or fill each step manually
3. Submit on the Review step

### Post-submission

The status page fetches and displays full entity details from the backend:
- Account Holder (type, status, KYC status, risk level)
- Legal Entity (business name, addresses, identifications)
- KYC Requirement (scope, status, document ID)

## Sample documents

Two sample PDFs are included in `public/` for testing AI extraction:

| File | Type | What it extracts |
|------|------|-----------------|
| `Memorandum_Association-compressed.pdf` | MOA | Company name, directors, shareholders, business activities, formation date |
| `UAE_Bank_Statement_Feb2025.pdf` | Bank Statement | Account holder, transactions, monthly volume |

Source: `../document-processing/` (the research/prototyping folder)

## Running tests

```bash
# All E2E tests (requires all 3 services running)
pnpm e2e

# Headed mode (opens browser)
pnpm e2e:headed

# Specific test
pnpm exec playwright test e2e/ai-extraction.spec.ts
pnpm exec playwright test e2e/onboarding-m1.spec.ts
```

### Test descriptions

| Test | What it covers |
|------|---------------|
| `onboarding-m1.spec.ts` | Full M1 flow: form fill → submit → backend creates AccountHolder + LegalEntity + KYC → backend verification |
| `ai-extraction.spec.ts` | Upload MOA + bank statement → AI extraction → verify prefilled identity, directors, UBOs |

## Project structure

```
src/
  features/
    onboarding/          # Form wizard, steps, types, API client
      api.ts             # SDK calls (create + fetch AccountHolder, LegalEntity, KYC)
      types.ts           # Application, Director, UBO, Address, etc.
      components/steps/  # StepDocuments, StepIdentity, StepReview, etc.
    documents/           # Document upload, classification, verification
      extraction.ts      # AI extraction API client + mapping to Application fields
      classifier.ts      # Filename → document type classification
      verification.ts    # Client-side document verification
      samples.ts         # Sample documents with hardcoded prefill data
    ops/                 # Post-submission status page
e2e/                     # Playwright E2E tests
public/                  # Sample PDFs for AI extraction testing
```

## Environment variables

### Frontend (`.env.local`)

| Variable | Required | Description |
|----------|----------|-------------|
| `VITE_API_KEY` | For backend submission | Atomic FI API key from bootstrap creds |
| `VITE_TENANT_ID` | For backend submission | Tenant UUID |

### Document extraction (Phoenix `POST /api/parse`)

Extraction now happens in Phoenix; the Python service is gone.
Configure via env vars at the Phoenix process — set in
`config/runtime.exs` from these env vars (defaults are local Ollama):

| Variable | Default | Description |
|----------|---------|-------------|
| `OLLAMA_VISION_MODEL` | `llama3.2-vision:11b` | Vision model for `/api/parse` |
| `LITER_LLM_BASE_URL` | `http://localhost:11434/v1` | OpenAI-compatible endpoint (Ollama by default) |
