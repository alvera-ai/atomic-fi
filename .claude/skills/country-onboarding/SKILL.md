---
name: country-onboarding
description: Onboard a country's compliance regime — adds sanctions lists to Watchman, creates ZenRule rules for that jurisdiction, generates test corpus, and suggests Lotus probes. Use whenever the user wants to "add a country", "onboard India/France/UAE", "set up compliance for country X", or any phrasing that maps a country to sanctions lists + rules + test data.
---

# country-onboarding

Onboard a single country's compliance regime end-to-end: sanctions data into Watchman, jurisdiction-specific rules into ZenRule, test corpus to prove them, Lotus probes to query results.

---

## Invocation

```
/country-onboarding --country AE     # UAE
/country-onboarding --country IN     # India
/country-onboarding --country FR     # France
/country-onboarding --country ID     # Indonesia
```

ISO 3166-1 alpha-2 country code. Any country — the skill discovers available sanctions lists dynamically from OpenSanctions.

---

## Workflow

```
1. DISCOVER    →  Query OpenSanctions index for datasets matching the country code.
                   Print available lists + entity counts.
2. WATCHMAN    →  For each relevant dataset:
                   a. Download entities.ftm.json from OpenSanctions
                   b. Convert FTM → Senzing JSONL (Watchman's ingest format)
                   c. Append to custom-watchlist.jsonl
                   d. Restart Watchman, verify entities loaded
3. RULES       →  Research the country's AML/CFT regulations:
                   a. Find the country's FIU, central bank, or AML authority
                   b. Identify 2-5 country-specific rules derivable from current schema
                   c. Delegate each to scenario-author --regulation
4. ROLLUP      →  Print summary: entities loaded, rules created, proofs green
5. PROBES      →  Suggest Lotus SQL probes specific to this country
```

---

## Step 1 — DISCOVER

Query the OpenSanctions dataset index:

```bash
curl -s "https://data.opensanctions.org/datasets/latest/index.json"
```

Filter datasets whose `name` starts with the country's alpha-2 code (lowercase). Print:

```
Available sanctions lists for AE:
  ae_local_terrorists — United Arab Emirates Local Terrorist List (771 entities)
```

If no datasets found for the country code, log it and proceed to Step 3 (rules only, no Watchman data). Not every country has an OpenSanctions dataset — that's fine.

---

## Step 2 — WATCHMAN (sanctions data)

### 2a. Download

```bash
curl -sL -o /tmp/<dataset>.ftm.json \
  "https://data.opensanctions.org/datasets/latest/<dataset>/entities.ftm.json"
```

If the download fails or returns HTML (Cloudflare), try the `.json.gz` variant and gunzip. If both fail, skip this dataset and log the failure.

### 2b. Convert FTM → Senzing JSONL

OpenSanctions FTM (FollowTheMoney) entities have this shape:

```json
{"id": "...", "schema": "Person", "properties": {"name": ["..."], "birthDate": ["..."], "nationality": ["..."], ...}}
```

Convert each entity to Senzing JSONL (same format as `custom-watchlist.jsonl`):

```json
{"DATA_SOURCE": "<DATASET_UPPER>", "RECORD_ID": "<ftm_id>", "RECORD_TYPE": "PERSON|ORGANIZATION", "NAME_FULL": "...", "DATE_OF_BIRTH": "...", "NATIONALITY": "...", "ADDR_COUNTRY": "..."}
```

Mapping:

| FTM schema | Senzing RECORD_TYPE | Name field |
|---|---|---|
| `Person` | `PERSON` | `NAME_FULL` from `properties.name[0]` |
| `Organization` | `ORGANIZATION` | `NAME_ORG` from `properties.name[0]` |
| `LegalEntity` | `ORGANIZATION` | `NAME_ORG` |
| `Company` | `ORGANIZATION` | `NAME_ORG` |

Write the conversion as a Python one-liner or small script. Use `python3` (available in the environment).

### 2c. Append to watchlist

```bash
cat /tmp/<dataset>.senzing.jsonl >> custom-watchlist.jsonl
```

### 2d. Restart Watchman and verify

```bash
docker compose -f local-dependencies.yaml restart watchman
```

Wait for health check, then verify a known entity from the dataset is findable:

```bash
curl -s "http://localhost:8084/v2/search?name=<known_name>&limit=1"
```

If the entity appears with a match score, Watchman loaded the data successfully.

---

## Step 3 — RULES (country-specific ZenRule rules)

Research the country's AML/CFT regulatory framework. Every country has at minimum:

- A **Financial Intelligence Unit** (FIU) — e.g., FinCEN (US), CBUAE FIU (UAE), FIU-IND (India), TRACFIN (France), PPATK (Indonesia)
- **CTR thresholds** — every jurisdiction has a cash transaction reporting threshold
- **STR/SAR obligations** — suspicious transaction reporting
- **Sanctions compliance** — domestic designated persons list

For each derivable rule:
1. Find the regulation text (prefer the country's official gazette, central bank website, or FIU website)
2. Delegate to `scenario-author --regulation <url-or-saved-text>` for the proof loop
3. If the regulation can't be fetched (gov site blocks automated access), save the relevant text to `.regulations/<country>/<slug>.txt` and pass the local path

### Common rule patterns per country

| Pattern | Example (UAE) | Fields used |
|---|---|---|
| CTR threshold | Transactions ≥ AED 55,000 (≈$15k) | `amount`, `currency` |
| Domestic designated person | CBUAE Local Terrorist List match | Watchman search (Step 2 data) |
| Country-specific sanctions | UAE sanctions on Qatar (2017-2021) | `citizenship_country` |
| High-risk jurisdiction EDD | FATF grey list countries | `jurisdiction_cooperative` |
| PEP screening | Local PEP database | `politically_exposed_person` |

Do NOT create rules that require schema fields that don't exist. Check `.claude/skills/scenario-author/references/payload-schema.md` before drafting.

---

## Step 4 — ROLLUP

Print a summary:

```
Country: AE (United Arab Emirates)

Watchman:
  ae_local_terrorists — 771 entities loaded
  Verification: "Fatima Al Rashidi" → match 0.94 ✓

Rules created:
  ✓ uae_ctr_threshold — AED 55k CTR (proof green, match=3, mismatch=0)
  ✓ uae_designated_block — CBUAE designated person block (proof green, match=2, mismatch=0)

Coverage: 2 rules, 5 transactions, 0 mismatches
```

---

## Step 5 — PROBES

Suggest Lotus SQL probes specific to this country:

```sql
-- Transactions involving <country> entities
SELECT t.rejected_rule, count(*) as blocked
FROM transactions t
JOIN legal_entities le ON le.counterparty_id = t.creditor_counterparty_id
WHERE le.citizenship_country = '<CC>'
GROUP BY t.rejected_rule

-- Watchman matches for <country> dataset
SELECT sm.entity_name, sm.match_score, sm.source_list
FROM sanctions_matches sm
WHERE sm.source_list = '<dataset>'
ORDER BY sm.match_score DESC
```

---

## Hard rules

- **One country per invocation.** Don't batch countries — each has different datasets, regulations, and rule shapes.
- **No fabricated sanctions data.** Only use OpenSanctions (public, maintained, cited by FATF). Never invent entity names or make up sanctions lists.
- **No silent failures.** If OpenSanctions doesn't have a dataset for the country, say so. If a regulation can't be fetched, say so.
- **Delegate rule creation to scenario-author.** This skill orchestrates; it does not draft JDM rules directly.
- **Never auto-commit.** The user reviews Watchman data additions and rule changes before committing.
- **Verify Watchman loaded the data.** Don't assume — search for a known entity after restart.
- **Proceed without confirmation.** After completing each step, move to the next. Don't ask "Shall I continue?"

---

## Reference files

- **`references/opensanctions-ftm-format.md`** — FTM entity schema and Senzing JSONL conversion mapping
- **`references/country-fiu-directory.md`** — FIU names and regulation URLs per country

## Related

- [generate-rules](../generate-rules/SKILL.md) — multi-URL rule generation (Step 3 delegates here)
- [scenario-author](../scenario-author/SKILL.md) — per-rule proof loop
- [master-suite](../master-suite/SKILL.md) — run all rules together after onboarding
