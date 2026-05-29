# master.md Format

## Structure

```markdown
# Correctness Verification — Master Proof

Generated: <ISO 8601 timestamp>
URLs processed: N/N (M skipped)

## Table of Contents

| # | Slug | Regime | Cite | Verdict Mix | Status |
|---|------|--------|------|-------------|--------|
| 1 | ofac_sdn_match | OFAC | 31 CFR §501 | match=2 | ✓ |
| 2 | ctr_structuring | BSA | 31 USC §5324 | match=4 | ✓ |

## Overall Summary

| Status | Count |
|--------|-------|
| Total proofs | N |
| All green | N |
| Skipped | M |
| Total transactions verified | T |

---

## 1. ofac_sdn_match

<verbatim contents of corpus/zen_rules/ofac_sdn_match/proof.md>

---

## 2. ctr_structuring

<verbatim contents of corpus/zen_rules/ctr_structuring/proof.md>
```

## Rules

- Each proof section is a verbatim copy of the scenario's `proof.md`
- No editing, no summarizing — the regulator reads the raw proof
- Create the `benchmarks/correctness/` directory if it doesn't exist
- Output path: `benchmarks/correctness/master.md`
