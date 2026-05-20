# atomic-fi-scenarios (Bruno collection)

The single Bruno collection for every atomic-fi scenario — one folder per scenario, one `.bru` file per HTTP request. Today contains **one baseline smoke + ten regulatory scenarios** drawn from [`guides/use-cases.md`](../../guides/use-cases.md). Each scenario folder is self-contained (its own auth + warmup prelude) so it can be run on its own, or you can Recursive-Run the whole collection from the root for a full demo.

## Layout

```
bruno/atomic-fi-scenarios/
├── bruno.json
├── collection.bru               ← collection-level docs + Scenario catalog
├── README.md                    ← this file
├── environments/
│   ├── local.example.bru        ← committed template
│   └── local.bru                ← gitignored, you fill in
│
├── smoke-tests/                 ← 29 reqs — baseline data seed (no regulation tested)
│
├── de-minimis-ach/              ← 7  reqs — §1 CIP min-info — PASS
├── cip-kyc-in-progress/         ← 9  reqs — §6 BSA §326 CIP gate — BLOCK→PASS
├── prohibited-risk-freeze/      ← 7  reqs — §10 CDD risk-class freeze — BLOCK
├── ofac-sdn-high-score/         ← 11 reqs — §11 OFAC SDN — BLOCK→false-positive→PASS
├── ah-country-kp-residence/     ← 9  reqs — §15 OFAC E.O. 13466 (DPRK) — BLOCK→PASS
├── ctr-sub-threshold-structuring/ ← 9 reqs — §19 31 USC §5324 — PASS×2→BLOCK
├── smurfing-pattern-sar-eligible/ ← 22 reqs — §20 smurfing typology — PASS×5→BLOCK
├── business-ah-zero-bos/        ← 9  reqs — §27 CTA / FinCEN CDD UBO — BLOCK→PASS
├── ofac-mixer-usdc/             ← 7  reqs — §34 OFAC mixer + GENIUS Act — BLOCK
└── internal-blocklist-lastname/ ← 10 reqs — §41 FFIEC internal-list — BLOCK
```

See `collection.bru` ("Scenario detail" section) or the Bruno Overview tab for the regulatory narrative behind each folder.

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

## Run a scenario (single click)

1. Click on any scenario folder in the sidebar (e.g. **`smoke-tests`**, **`ofac-sdn-high-score`**, **`cip-kyc-in-progress`**).
2. Switch to the **Runner** tab in the main panel.
3. Click **Recursive Run**.

Every scenario folder is self-contained — it begins with its own `001-auth.bru` + `002-warmup.bru`, so any folder can be run on its own, in any order, idempotently. Recursive-Run from the collection root walks every folder.

CLI form:

```bash
cd bruno/atomic-fi-scenarios
bru run smoke-tests           --env local   # baseline seed
bru run ofac-sdn-high-score   --env local   # OFAC SDN BLOCK → false-positive → PASS
bru run cip-kyc-in-progress   --env local   # BSA §326 BLOCK → kyc approved → PASS
# …etc, one per folder
```

Smoke end-state: **2 account holders, 5 counterparties, 20 transactions** in the local DB, ~10 seconds wall time. Regulatory scenarios leave their own AHs / CPs / TXs behind with the documented verdicts attached.

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

## Scenario catalog (regulation tested)

| Folder | Catalog # | Regulation | Lifecycle |
|---|---|---|---|
| `smoke-tests/` | — | baseline data seed (no regulation tested) | all pass |
| `de-minimis-ach/` | #1 | 31 CFR §1020.220 — CIP minimum thresholds | PASS |
| `cip-kyc-in-progress/` | #6 | BSA §326 / 31 CFR §1020.220 — CIP identity verification | BLOCK → PUT `kyc_status:approved` → PASS |
| `prohibited-risk-freeze/` | #10 | 31 CFR §1010.230 (CDD) + lawful-order freeze | BLOCK (`risk_level: prohibited`) |
| `ofac-sdn-high-score/` | #11 | 31 CFR §501.404 — OFAC SDN screening | BLOCK → mark false-positive → PASS |
| `ah-country-kp-residence/` | #15 | OFAC E.O. 13466 — comprehensive DPRK sanctions | BLOCK → PUT residence → PASS |
| `ctr-sub-threshold-structuring/` | #19 | 31 USC §5324 + 31 CFR §1020.320 — structuring | PASS × 2 → BLOCK on velocity |
| `smurfing-pattern-sar-eligible/` | #20 | 31 USC §5324 + 31 CFR §1020.320 — smurfing typology | PASS × 5 → BLOCK (SAR eligible) |
| `business-ah-zero-bos/` | #27 | Corporate Transparency Act / 31 CFR §1010.380 — FinCEN CDD UBO | BLOCK → POST beneficial owner → PASS |
| `ofac-mixer-usdc/` | #34 | 31 CFR §501.404 + GENIUS Act §4(a)(5) — mixer wallet | BLOCK on recipient wallet |
| `internal-blocklist-lastname/` | #41 | FFIEC BSA/AML Manual — internal-list screening | seed entry → refresh cache → BLOCK |

Each folder asserts the verdict the catalog promises (`PASS` / `REVIEW` / `BLOCK` / `FREEZE`) by inspecting `GET /api/transactions/:id` status + `GET /api/compliance-screenings/...` rule_id and verdict. Recursive Run on the collection root walks every folder in order; each folder also runs standalone via `bru run <folder> --env local`. Full regulatory narrative per scenario lives in `collection.bru` (Bruno Overview tab → "Scenario detail").

## Future scenarios (see [#27](https://github.com/alvera-ai/atomic-fi/issues/27))

Catalog scenarios not yet wired up — wishlist drawn from [`guides/use-cases.md`](../../guides/use-cases.md):

- PEP / adverse-media screening
- Custom per-tenant watchlists
- Fail-closed behaviour (Watchman / Postgres unavailable)
- Continuing SAR (90-day re-file cadence)
- Fraud / account-event velocity
- Disposition evidence retention
- Positive-controls (allow-list overrides)
- OFAC 50%-rule / sanctioned-band derivation

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `001-auth.bru` returns **422** | `local.bru` missing or has empty `adminPassword` / `rootApiKey` | Re-copy from `local.example.bru`; defaults work against the standard dev tenant |
| `001-auth.bru` returns **connection refused** | atomic-fi backend isn't running | `make server` in the repo root |
| Recursive Run only fires the auth | Old subfolder structure cached by Bruno | Reload the collection (right-click `atomic-fi-scenarios` → Reload) |
| AH / CP creates succeed but Phoenix logs show `BlocklistCache not initialized` | The `002-warmup.bru` request was skipped | Re-run from `001-auth.bru`; the warmup must precede AH/CP creates |
| AH / CP creates succeed but Phoenix logs show `Req.TransportError: connection refused` | Watchman screening worker can't reach the Watchman container | Either start Watchman (`make run-watchman`) or ignore — `chain_screening: false` means the smoke itself is unaffected |
| TX creates fail with "No seeded AHs/CPs in env" | The Recursive Run got out of order | Re-run from `001-auth.bru`; Run All on the folder respects file ordering |
