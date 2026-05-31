# Rollup Output Format

## Per-rule summary

One block per rule that fired, sorted by hit count descending:

```
─── ofac_sdn_match ───────────────────────────────
hits         412
verdicts     BLOCK 380 · REVIEW 26 · PASS 6
blocked AH   4   blocked Txn 380
cite         OFAC SDN List · 31 CFR §501

─── ctr_structuring ──────────────────────────────
hits         245
verdicts     BLOCK 220 · REVIEW 18 · PASS 7
blocked AH   0   blocked Txn 220
cite         31 USC §5324

─── cip_kyc_not_approved ─────────────────────────
hits         198
verdicts     BLOCK 198
blocked AH   10   blocked Txn 198
cite         BSA §326 · 31 CFR §1020.220
```

Fields per block:
- **hits** — total transactions where this rule fired (`rejected_rule == slug`)
- **verdicts** — breakdown by transaction status. Map `rejected` → BLOCK, `accepted` → PASS. `rejected_code: "REVIEW"` → REVIEW.
- **blocked AH** — count of distinct AHs whose transactions were blocked by this rule
- **blocked Txn** — count of transactions blocked by this rule
- **cite** — regulatory citation from the `_label` of the first matching transaction

## Overall rollup

One-line summary:

```
TOTAL  PASS 8740 · REVIEW 217 · BLOCK 1041 · FREEZE 2 · coverage 10/10 rules
```

If coverage < 100%, list which rules did NOT fire and why.

## Accuracy summary

```
Accuracy: match=9842 · mismatch=158 · new=0 · setup_error=0 · engine_error=0
```

## Computing from run_vu results

Each `run_vu` result row has:

```elixir
%{
  external_id: "ms-txn-00001",
  label: %{"regime" => "ofac", "cite" => "31 CFR §501", ...},
  expected: %{"status" => "rejected", "rejected_rule" => "ofac_sdn_match"},
  actual: %{"status" => "rejected", "rejected_rule" => "ofac_sdn_match", ...},
  status: :match,  # or :mismatch, :new, :setup_error, :engine_error
  elapsed_ms: 12
}
```

Group by `actual["rejected_rule"]` for per-rule summary. Aggregate `actual["status"]` for overall rollup.
