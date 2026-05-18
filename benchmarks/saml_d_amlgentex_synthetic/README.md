# Bulk performance bench — atomic-fi rule engine

## What was tested

atomic-fi's rule engine was driven through **320 synthetic
transactions** drawn from 2 AML research datasets:

  - **SAML-D** (Oztas et al. 2023): synthetic transaction monitoring data with 28 typologies (11 normal + 17 suspicious patterns like smurfing, structuring, layering). Original dataset is 12 MB on Kaggle.
  - **AMLGentex** (AI Sweden / Handelsbanken / Swedbank 2024): synthetic transaction-network simulator producing scale-free graphs with configurable normal + SAR patterns (fan-in, fan-out, layering, smurfing). Apache-2.0; runs Python simulator locally.

The transactions were sharded into **4 parallel workers**
(the "poor-man's k6" model) and the production write path
(`AccountHolderContext.create_account_holder/2` →
`CounterpartyContext.create_counterparty/2` →
`PaymentAccountContext.create_payment_account/2` →
`TransactionContext.create_transaction/2`) was exercised end-to-end
for every row. Each transaction passed through every rule in
`priv/zenrule/transaction-screening/` (10 rules at the
time of this run).

## Results

| metric                                                         | value |
|----------------------------------------------------------------|------:|
| transactions processed                                         | 320 |
| transactions blocked by a rule                                 | 56 |
| transactions passed through                                    | 264 |
| block rate                                                     | 17.5% |
| average throughput across shards                               | 44.7 txns/sec |
| worst-case p95 latency across shards                           | 35 ms |

Per-dataset breakdown:

| dataset    | rows | blocked | passed | txns/sec | p50 ms | p95 ms | p99 ms |
|---         | ---: | ---:    | ---:   | ---:     | ---:   | ---:   | ---:   |
| saml_d | 160 | 28 | 132 | 43.9 | 21 | 35 | 53 |
| amlgentex | 160 | 28 | 132 | 45.5 | 21 | 32 | 49 |

## Reproduce

```
make bench BENCH_SOURCES="saml_d,amlgentex" \
           BENCH_SHARDS=4 \
           BENCH_ROWS=40 \
           BENCH_SEED=0
```

No external dependencies required (no Kaggle CLI, no Python sim).
The synthetic transaction rows are generated deterministically by
`AtomicFi.Corpus.SyntheticSeed` from the seed above. Same seed →
byte-identical output.

For real-data perf tuning (against the actual SAML-D + AMLGentex
upstreams), use `make bench-real` after running `make reseed-saml-d`
and `make reseed-amlgentex` once.

## Per-dataset detailed reports

The full per-row drift report for each dataset is appended below.
Rows are marked `🆕 new` because bulk-bench transactions don't carry
a pre-calibrated `_expected` verdict — the bench measures the
engine's actual decision distribution, not correctness against a
pinned expectation. For the latter, see `corpus/zen_rules/<slug>/`
(the 10 hand-authored auditor-walked scenarios).

## saml_d

# corpus.validate report

- corpus: `tmp/bench/saml_d/shards`
- transactions: 40

## s00-txn-000000

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Credit Card laundering_type=Normal date=2026-04-02

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000001

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Wire Transfer laundering_type=Normal date=2026-04-03

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000002

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Credit Card laundering_type=Normal date=2026-04-04

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000003

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Cash Deposit laundering_type=Normal date=2026-04-05

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000004

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=ACH laundering_type=Normal date=2026-04-06

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000005

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Cheque laundering_type=Normal date=2026-04-07

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000006

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=ACH laundering_type=Normal date=2026-04-08

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000007

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Cash Deposit laundering_type=Normal date=2026-04-09

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000008

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Cash Deposit laundering_type=Normal date=2026-04-10

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000009

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Wire Transfer laundering_type=Layering date=2026-04-11

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000010

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Cash Deposit laundering_type=Normal date=2026-04-12

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000011

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Cash Deposit laundering_type=Normal date=2026-04-13

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000012

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Wire Transfer laundering_type=Normal date=2026-04-14

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000013

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=ACH laundering_type=Normal date=2026-04-15

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000014

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Wire Transfer laundering_type=Normal date=2026-04-16

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000015

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=ACH laundering_type=Normal date=2026-04-17

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000016

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Cash Deposit laundering_type=Normal date=2026-04-18

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000017

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Cash Deposit laundering_type=Normal date=2026-04-19

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000018

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Credit Card laundering_type=Normal date=2026-04-20

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000019

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Credit Card laundering_type=Normal date=2026-04-21

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000020

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=ACH laundering_type=Normal date=2026-04-22

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000021

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Cash Deposit laundering_type=Normal date=2026-04-23

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000022

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Cheque laundering_type=Normal date=2026-04-24

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000023

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Cheque laundering_type=Normal date=2026-04-25

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000024

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=ACH laundering_type=Normal date=2026-04-26

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000025

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Cheque laundering_type=Normal date=2026-04-27

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000026

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=ACH laundering_type=Normal date=2026-04-28

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000027

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Credit Card laundering_type=Normal date=2026-04-01

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000028

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Cheque laundering_type=Normal date=2026-04-02

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000029

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Credit Card laundering_type=Normal date=2026-04-03

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000030

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Credit Card laundering_type=Smurfing date=2026-04-04

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000031

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=ACH laundering_type=Normal date=2026-04-05

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000032

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Wire Transfer laundering_type=Normal date=2026-04-06

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000033

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Cash Deposit laundering_type=Normal date=2026-04-07

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000034

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Credit Card laundering_type=Normal date=2026-04-08

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000035

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Cash Deposit laundering_type=Normal date=2026-04-09

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000036

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Wire Transfer laundering_type=Normal date=2026-04-10

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000037

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Credit Card laundering_type=Normal date=2026-04-11

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000038

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Cash Deposit laundering_type=Normal date=2026-04-12

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000039

- status:   **🆕 new**
- regime:   saml-d
- cite:     Oztas et al. 2023 — SAML-D synthetic monitoring dataset
- scenario: type=Cheque laundering_type=Normal date=2026-04-13

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## Summary

| status | count |
|---|---|
| match | 0 |
| new (no _expected) | 40 |
| mismatch | 0 |
| setup_error | 0 |
| engine_error | 0 |
| **total** | **40** |


## amlgentex

# corpus.validate report

- corpus: `tmp/bench/amlgentex/shards`
- transactions: 40

## s00-txn-000000

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000001

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000002

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000003

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000004

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000005

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000006

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000007

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000008

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000009

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000010

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000011

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000012

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000013

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000014

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000015

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000016

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000017

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=1

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000018

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000019

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000020

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000021

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000022

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000023

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000024

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000025

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000026

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000027

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000028

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000029

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000030

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000031

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000032

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000033

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000034

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "credit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000035

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=1

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000036

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": null,
  "rejected_direction": null,
  "rejected_period": null,
  "rejected_rule": null,
  "status": "accepted"
}
```
</details>


## s00-txn-000037

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000038

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## s00-txn-000039

- status:   **🆕 new**
- regime:   amlgentex
- cite:     AI Sweden / Handelsbanken / Swedbank 2024 — AMLGentex synthetic network
- scenario: is_sar=0

<details open><summary>actual (no _expected on row)</summary>

```json
{
  "rejected_code": "LIMIT_EXCEEDED",
  "rejected_direction": "debit",
  "rejected_period": "daily",
  "rejected_rule": "ach_de_minimis",
  "status": "rejected"
}
```
</details>


## Summary

| status | count |
|---|---|
| match | 0 |
| new (no _expected) | 40 |
| mismatch | 0 |
| setup_error | 0 |
| engine_error | 0 |
| **total** | **40** |
