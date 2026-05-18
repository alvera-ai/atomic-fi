# Bulk performance bench — atomic-fi rule engine

> k6-shape VU sweep. Each VU is one parallel iteration of a
> catalog scenario (round-robin across the 10 scenarios
> under `corpus/zen_rules/`). Within a VU the transactions run
> sequentially (velocity rules need arrival order); across VUs the
> runs are independent (each VU has a UUID-prefixed external_id
> namespace, no cross-VU sharing).

## Test environment

| component | value |
|---|---|
| run date          | `2026-05-18T22:11:30Z` |
| CPU               | Apple M2 Max |
| CPU cores         | 12 |
| load average pre-test (1m / 5m / 15m) | `7.23 7.69 5.89` |
| OS / kernel       | Darwin 25.4.0 arm64 |
| Elixir            | 1.18.3 |
| Erlang / OTP      | 27 |
| Postgres          | psql (PostgreSQL) 17.6 (Homebrew) |
| ZenRule (agent)   | `local` |
| rule count        | 10 |
| DB pool size      | 10 |
| VU ladder         | 10, 100, 1000, 10000 |

## Rules under test (10)

Every transaction in this run was evaluated against all
`priv/zenrule/transaction-screening/` rules in parallel; the
per-rule outputs were folded into one effective control per
ledger account before the transaction was either accepted or
rejected with a `rejected_rule`.

| rule | regulatory cite | payload field read |
|---|---|---|
| `de_minimis_stablecoin` | 31 CFR §1020.220 | `creditor_payment_account.account_holder.kyc_status` |
| `cip_kyc_gate` | BSA §326 (31 CFR §1020.220) | `account_holder.kyc_status` |
| `ofac_sdn_match` | OFAC 31 CFR §501.404; §501.603 | `creditor_payment_account.compliance_screenings[].sanctions_matches[]` |
| `ctr_structuring` | BSA §5324; 31 CFR §1020.320 | `account_holder.recent_debits_24h[] (sub-CTR amount band)` |
| `smurfing_pattern_sar_eligible` | BSA §5324; 31 CFR §1020.320 | `account_holder.recent_debits_24h[] (≥6 distinct creditor PAs ≤ smurf_max)` |
| `prohibited_risk_freeze` | Internal policy; 31 CFR §1010.230 | `account_holder.risk_level` |
| `ah_country_kp_residence` | OFAC E.O. 13466 (KP); IR/CU/SY sets | `account_holder.legal_entity.addresses[] primary residential country` |
| `business_ah_zero_bos` | Corporate Transparency Act; 31 CFR §1010.380 | `account_holder.account_holder_type + beneficial_owners[]` |
| `internal_blocklist_lastname` | FFIEC BSA/AML Examination Manual | `creditor_payment_account.compliance_screenings[].blocklist_matches[]` |
| `stableaml_wallet_blocklist` | OFAC 31 CFR §501.404; GENIUS Act §4(a)(5) | `creditor_payment_account.wallet_address` |

## Catalog scenarios (10)

Each VU is one parallel iteration of one of these scenarios. Mix of
happy-path, BSA/OFAC blocks, CIP gates, and stablecoin/sanctions
flows — the full live-platform surface, not a synthetic micro-bench.

- `de_minimis_stablecoin`
- `cip_kyc_gate`
- `ofac_sdn_match`
- `ctr_structuring`
- `smurfing_pattern_sar_eligible`
- `prohibited_risk_freeze`
- `ah_country_kp_residence`
- `business_ah_zero_bos`
- `internal_blocklist_lastname`
- `stableaml_wallet_blocklist`

## VU sweep

| VUs | wall (ms) | txns | matches | blocked | mismatches | setup err | engine err | crashes | txns/sec | p50 (ms) | p95 (ms) | p99 (ms) |
| ---:| ---:      | ---: | ---:    | ---:    | ---:       | ---:      | ---:       | ---:    | ---:     | ---:     | ---:     | ---:     |
| 10 | 1778 | 56 | 56 | 30 | 0 | 0 | 0 | 0 | 31.5 | 15 | 30 | 31 |
| 100 | 10241 | 560 | 560 | 300 | 0 | 0 | 0 | 0 | 54.7 | 26 | 45 | 51 |
| 1000 | 46027 | 2205 | 2205 | 1195 | 0 | 0 | 0 | 637 | 47.9 | 119 | 192 | 258 |
| 10000 | 5903 | 98 | 98 | 54 | 0 | 0 | 0 | 9985 | 16.6 | 21 | 38 | 39 |

## VUs 10

Wall: 1778 ms · txns: 56 · throughput: 31.5 txns/sec
· matches: 56 · blocked: 30 · mismatches: 0
· setup_errors: 0 · engine_errors: 0 · vu_crashes: 0
· p50 15 ms · p95 30 ms · p99 31 ms


## VUs 100

Wall: 10241 ms · txns: 560 · throughput: 54.7 txns/sec
· matches: 560 · blocked: 300 · mismatches: 0
· setup_errors: 0 · engine_errors: 0 · vu_crashes: 0
· p50 26 ms · p95 45 ms · p99 51 ms


## VUs 1000

Wall: 46027 ms · txns: 2205 · throughput: 47.9 txns/sec
· matches: 2205 · blocked: 1195 · mismatches: 0
· setup_errors: 0 · engine_errors: 0 · vu_crashes: 637
· p50 119 ms · p95 192 ms · p99 258 ms

**VU crashes (637 total, first 3 shown):**

- `corpus/zen_rules/ctr_structuring`: Finch was unable to provide a connection within the timeout due to excess queuing for connections. Consider adjusting the pool size, count, timeout or reducing the rate of requests if it is possible that the downstream service is unable to keep up with the current rate.

- `corpus/zen_rules/stableaml_wallet_blocklist`: Finch was unable to provide a connection within the timeout due to excess queuing for connections. Consider adjusting the pool size, count, timeout or reducing the rate of requests if it is possible that the downstream service is unable to keep up with the current rate.

- `corpus/zen_rules/smurfing_pattern_sar_eligible`: Finch was unable to provide a connection within the timeout due to excess queuing for connections. Consider adjusting the pool size, count, timeout or reducing the rate of requests if it is possible that the downstream service is unable to keep up with the current rate.



## VUs 10000

Wall: 5903 ms · txns: 98 · throughput: 16.6 txns/sec
· matches: 98 · blocked: 54 · mismatches: 0
· setup_errors: 0 · engine_errors: 0 · vu_crashes: 9985
· p50 21 ms · p95 38 ms · p99 39 ms

**VU crashes (9985 total, first 3 shown):**

- `task_exit`: {%DBConnection.ConnectionError{message: "[Elixir.AtomicFi.Repo] connection not available and request was dropped from queue after 445ms. This means requests are coming in and your connection pool cann
- `corpus/zen_rules/ah_country_kp_residence`: [Elixir.AtomicFi.Repo] connection not available and request was dropped from queue after 1181ms. This means requests are coming in and your connection pool cannot serve them fast enough. You can address this by:

  1. Ensuring your database is available and that you can connect to it
  2. Tracking down slow queries and making sure they are running fast enough
  3. Increasing the pool_size (although this increases resource consumption)
  4. Allowing requests to wait longer by increasing :queue_target and :queue_interval

See DBConnection.start_link/2 for more information

- `corpus/zen_rules/stableaml_wallet_blocklist`: [Elixir.AtomicFi.Repo] connection not available and request was dropped from queue after 893ms. This means requests are coming in and your connection pool cannot serve them fast enough. You can address this by:

  1. Ensuring your database is available and that you can connect to it
  2. Tracking down slow queries and making sure they are running fast enough
  3. Increasing the pool_size (although this increases resource consumption)
  4. Allowing requests to wait longer by increasing :queue_target and :queue_interval

See DBConnection.start_link/2 for more information



## Reproduce

```
make bench BENCH_LEVELS=10,100,1000,10000
```

## How this report is generated

`mix corpus.bench` runs the whole sweep in one BEAM:

1. Collects the test environment fingerprint.
2. Drops + remigrates the `atomic_fi_corpus` Postgres schema
   ONCE at the start (not per-VU — fresh schema gives every enum
   a fresh Postgrex type OID; one reset per BEAM is enough).
3. Loads the 10 catalog scenarios from
   `corpus/zen_rules/<slug>/` into memory, seeds their union of
   blocklist entries once.
4. For each VU level N, spawns `Task.async_stream(0..N-1, …)`
   — each task picks a scenario round-robin, generates a fresh
   UUID id-prefix, and runs the scenario's full insert + txn
   pipeline serially within the task.
5. Folds per-VU results into one row per level + writes this report.

See `lib/mix/tasks/corpus.bench.ex` and
`lib/atomic_fi/corpus/scenario_runner.ex`.
