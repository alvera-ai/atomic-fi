# Payments Screening

A demo frontend for the atomic-fi compliance platform. It runs the four
**stateless preview-screening** endpoints and renders the verdict, a per-check
breakdown, and any sanctions matches.

| Screener | Endpoint |
| --- | --- |
| Account Holder | `POST /api/compliance-screenings/screen-account-holder` |
| Beneficial Owner | `POST /api/compliance-screenings/screen-beneficial-owner` |
| Counterparty | `POST /api/compliance-screenings/screen-counterparty` |
| Payment Account | `POST /api/compliance-screenings/screen-payment-account` |

Each returns `{ data: ComplianceScreening[] }` — one row per screening type
(sanctions, PEP, AML, adverse media). The app rolls the rows into a single
headline verdict (match → review → cleared) and lists the detail.

## Run

```bash
pnpm install          # from the repo root (pnpm workspace)
pnpm --filter payments-screening dev
```

Open <http://localhost:4200>. The API must be running (see the repo
`INSTALLATION.md` — `docker compose up` serves it on `:4100`).

The browser cannot call the Phoenix API cross-origin (it sends no CORS
headers), so the dev server proxies same-origin `/api/*` to the API. Point the
proxy elsewhere with `VITE_API_PROXY`:

```bash
VITE_API_PROXY=http://localhost:4100 pnpm --filter payments-screening dev
```

## Configuration

**Settings** holds the two connection fields, persisted to `localStorage`:

- **Base URL** — blank routes through the dev proxy. Set an absolute URL to
  call a deployment directly (that origin must allow CORS).
- **API key** — sent as the `X-API-Key` header (M2M auth). Local dev default:
  `alvera_root_api_key_dev`. The tenant is resolved from this key via
  `GET /api/tenants` and injected into every screening request.

## Presets

Each screener ships demo payloads: a sanctions hit (Vladimir Putin) and a clean
pass (Roger Federer). Click one, then **Run screening**.

> The demo dataset loads sanctions lists only (OFAC, UN, FinCEN). PEP/AML flags
> and crypto-address matches are not produced by these lists, so those verdicts
> won't appear without additional data on the server.

## Scripts

```bash
pnpm --filter payments-screening typecheck   # tsc --noEmit
pnpm --filter payments-screening build        # tsc -b && vite build
pnpm --filter payments-screening lint         # eslint
```

## Stack

Vite + React + TypeScript + Tailwind v4. Radix Select, lucide icons, sonner
toasts. Talks to the API with plain `fetch` (no SDK dependency).
