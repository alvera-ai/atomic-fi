# atomic-fi-smoke (Bruno collection)

Click-to-run smoke + seed for atomic-fi. Single Run All click → 29 sequential requests → DB has **2 account holders, 5 counterparties, 20 transactions**. Demo-givers run this once before a meeting so the UI looks alive; new developers run this on first clone to feel what the API does.

## One-time setup

1. Install Bruno: `brew install --cask bruno` (or download from <https://www.usebruno.com>)
2. Bring atomic-fi up locally (in repo root): `make server`
3. Copy the env template:
   ```bash
   cp bruno/atomic-fi-smoke/environments/local.example.bru \
      bruno/atomic-fi-smoke/environments/local.bru
   ```
   Defaults already match the standard seeded admin tenant from `priv/repo/seed_migrations/`. If your local instance uses different credentials, edit `local.bru`.
4. In Bruno: **File → Open Collection** → select `bruno/atomic-fi-smoke/`
5. Top-right environment dropdown → select **local**

## Run the smoke (single click)

1. Click on the **`00-seed`** folder in the sidebar
2. Switch to the **Runner** tab in the main panel
3. Click **Run** (no iteration count needed; each file is a single request)

29 requests fire in sequence (`001-auth.bru` → `029-tx.bru`), ~10 seconds wall time. Result panel shows green per request.

## What each request does

| Files | Count | Purpose |
|---|---|---|
| `001-auth.bru` | 1 | POST `/api/sessions` — captures `authBearer` and `tenantId` env vars; resets the running `ahIds` / `cpIds` arrays |
| `002-ah.bru` … `003-ah.bru` | 2 | POST `/api/account-holders` with **nested `legal_entity`** — atomically creates one LE + one AH per request (random first/last name, random DOB, US individual, KYC-approved, low-risk). Appends new AH id to env array. |
| `004-cp.bru` … `008-cp.bru` | 5 | POST `/api/counterparties` (random name, ~75% individual / 25% business, mostly US with occasional GB / DE / FR / BR / MX). Appends to env array. |
| `009-tx.bru` … `028-tx.bru` | 20 | POST `/api/transactions` — picks a random AH + random CP from the env arrays, random amount $5–$5000, random transaction type. Variety per iteration so the dashboard never looks staged. |

`chain_screening: false` is set on AH and CP creates so the seed runs even when Watchman isn't up. To exercise sanctions enrichment in the background, start Watchman first: `make run-watchman`.

## Why a Bruno collection (not a `mix` task)

Same artefact serves three audiences:
- **Demo-giver** — pre-loads the UI before a meeting
- **New developer** — sees the API surface in motion on first clone, every request and response visible
- **Reviewer / counsel** — no guessing what the platform did; Bruno's UI shows the full request + response + assertion trail

A `mix` task would be 5× faster but invisible. Bruno is the slower-but-watchable path; raw speed is Block 2's job (k6 / YCSB).

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `001-auth.bru` returns **422** | `local.bru` missing or has empty `adminPassword` / `rootApiKey` | Re-copy from `local.example.bru`; defaults work against the standard dev tenant |
| `001-auth.bru` returns **connection refused** | atomic-fi backend isn't running | `make server` in the repo root |
| `00-seed` Run All only fires the auth | Old subfolder structure cached by Bruno | Reload the collection (Collections sidebar → right-click `atomic-fi-smoke` → Reload) |
| AH / CP creates succeed but Phoenix logs show `Req.TransportError: connection refused` | Watchman screening worker can't reach the Watchman container | Either start Watchman (`make run-watchman`) or ignore — `chain_screening: false` means the seed itself is unaffected |
| TX creates fail with "No seeded AHs/CPs in env" | The Run All sequence got out of order | Re-run from `001-auth.bru`; Run All on the folder respects file ordering |
