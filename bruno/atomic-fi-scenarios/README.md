# atomic-fi-scenarios (Bruno collection)

The single Bruno collection for every atomic-fi scenario — one folder per scenario group. Today contains **`smoke-tests/`** (the click-to-run smoke that also leaves enough realistic data behind for a UI demo). Future folders (`01-aml/`, `02-ofac-sanctions/`, `03-fraud/`, etc.) will mirror the regulatory regimes in [`guides/use-cases.md`](../../guides/use-cases.md), one .bru file per scenario, all driven by Bruno's "Recursive Run" from the collection root.

## Layout

```
bruno/atomic-fi-scenarios/
├── bruno.json
├── README.md  ← this file
├── environments/
│   ├── local.example.bru   ← committed template
│   └── local.bru           ← gitignored, you fill in
└── smoke-tests/         ← 29 requests; one Recursive Run = full smoke
    ├── 001-auth.bru
    ├── 002-warmup.bru
    ├── 003-ah.bru          (×2)
    ├── 005-cp.bru          (×5)
    └── 010-tx.bru          (×20)
```

## One-time setup

1. Install Bruno: `brew install --cask bruno` (or download from <https://www.usebruno.com>)
2. Bring atomic-fi up locally (in repo root): `make server`
3. Copy the env template:
   ```bash
   cp bruno/atomic-fi-scenarios/environments/local.example.bru \
      bruno/atomic-fi-scenarios/environments/local.bru
   ```
   Defaults already match the standard seeded admin tenant from `priv/repo/seed_migrations/`. If your local instance uses different credentials, edit `local.bru`.
4. In Bruno: **File → Open Collection** → select `bruno/atomic-fi-scenarios/`
5. Top-right environment dropdown → select **local**

## Run the smoke (single click)

1. Click on the **`smoke-tests`** folder in the sidebar
2. Switch to the **Runner** tab in the main panel
3. Click **Recursive Run** (recurses through any subfolders that may exist later)

29 requests fire in sequence (`001-auth.bru` → `029-tx.bru`), ~10 seconds wall time. Result panel shows green per request. End state: **2 account holders, 5 counterparties, 20 transactions** in the local DB.

## What each smoke request does

| Files | Count | Purpose |
|---|---|---|
| `001-auth.bru` | 1 | POST `/api/sessions` — captures `authBearer` and `tenantId` env vars; resets the running `ahIds` / `cpIds` arrays |
| `002-warmup.bru` | 1 | POST `/api/tenants/refresh-blocklist-cache` — initialises the per-tenant `BlocklistCache` ETS table (otherwise the screening worker fails fast on the first AH/CP create) |
| `003-ah.bru` … `004-ah.bru` | 2 | POST `/api/account-holders` with **nested `legal_entity`** — atomically creates one LE + one AH per request. Faker provides random first/last name + DOB. KYC-approved, low-risk, US individual. Appends new AH id to env array. |
| `005-cp.bru` … `009-cp.bru` | 5 | POST `/api/counterparties` (random name, ~75% individual / 25% business, mostly US with occasional GB / DE / FR / BR / MX). Appends to env array. |
| `010-tx.bru` … `029-tx.bru` | 20 | POST `/api/transactions` — picks a random AH + random CP from the env arrays, random amount $5–$5000, random transaction type. Variety per iteration so the dashboard never looks staged. |

`chain_screening: false` is set on AH and CP creates so the smoke runs even when Watchman isn't up. To exercise sanctions enrichment in the background, start Watchman first: `make run-watchman`.

## Why this is the right artefact

Same collection serves three audiences without fragmenting:

- **Demo-giver** — runs the smoke once before a meeting, UI is alive
- **New developer** — clicks Recursive Run on first clone, sees the API surface in motion, every request and response visible
- **Reviewer / counsel** — every `*.bru` file is a plain-text scenario you can read and re-run; no engineering knowledge required to operate

A `mix` task would be 5× faster but invisible. Bruno is the slower-but-watchable path; raw speed is Block 2's job (k6 / YCSB benchmark — see [#25](https://github.com/alvera-ai/atomic-fi/issues/25)).

## Future folders (see [#27](https://github.com/alvera-ai/atomic-fi/issues/27))

As scenarios from [`guides/use-cases.md`](../../guides/use-cases.md) are wired up, each regulatory regime gets its own folder under this collection:

```
smoke-tests/                          ← exists today
01-aml-cip/                              ← future (BSA §326 — scenarios 6-10)
02-ofac-sanctions/                       ← future (OFAC SDN + 50% rule + bands)
03-edd-geo-corridor/                     ← future
04-structuring-velocity/                 ← future (BSA §5324)
05-cta-beneficial-ownership/             ← future
06-genius-act-stablecoin/                ← future
07-blocklist/                            ← future
08-pep-adverse-media/                    ← future
09-custom-watchlist/                     ← future
10-fail-closed/                          ← future
11-continuing-sar/                       ← future
12-fraud-account-event-velocity/         ← future
13-disposition-evidence/                 ← future
14-positive-controls/                    ← future
```

Recursive Run on the collection root walks every folder in order. Each scenario folder asserts the verdict the catalog promises (`PASS` / `REVIEW` / `BLOCK` / `FREEZE`) by inspecting `GET /api/transactions/:id` status + `GET /api/compliance-screenings?transaction_id=:id` rule_id and verdict.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `001-auth.bru` returns **422** | `local.bru` missing or has empty `adminPassword` / `rootApiKey` | Re-copy from `local.example.bru`; defaults work against the standard dev tenant |
| `001-auth.bru` returns **connection refused** | atomic-fi backend isn't running | `make server` in the repo root |
| Recursive Run only fires the auth | Old subfolder structure cached by Bruno | Reload the collection (right-click `atomic-fi-scenarios` → Reload) |
| AH / CP creates succeed but Phoenix logs show `BlocklistCache not initialized` | The `002-warmup.bru` request was skipped | Re-run from `001-auth.bru`; the warmup must precede AH/CP creates |
| AH / CP creates succeed but Phoenix logs show `Req.TransportError: connection refused` | Watchman screening worker can't reach the Watchman container | Either start Watchman (`make run-watchman`) or ignore — `chain_screening: false` means the smoke itself is unaffected |
| TX creates fail with "No seeded AHs/CPs in env" | The Recursive Run got out of order | Re-run from `001-auth.bru`; Run All on the folder respects file ordering |
