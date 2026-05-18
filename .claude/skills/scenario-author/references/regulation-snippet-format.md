# Reading a regulation snippet (`--regulation` mode)

When the user passes `--regulation <path>` instead of a catalog row, the skill reads the regulation, extracts the same five values a `use-cases.md` row provides, and proceeds as if it had read the row.

```
   regulation snippet           extraction template          downstream
   ──────────────────────       ─────────────────────        ──────────
   PDF / .txt / .md      ───▶  row_number? (TBD)      ───▶  Step 1 — Capture
                                slug                        Step 2 — Ground
                                rule_type                   Step 3 — Draft rule
                                verdict + rejected_rule     Step 4 — Draft corpus
                                schema needs                Step 5 — Proof loop
```

`row_number` may be unknown — that's fine. The skill drafts the slice; if the user later adds the row to `guides/use-cases.md`, the linkage is added then.

---

## Extraction template

For each snippet, fill in:

```
   ┌─────────────────────┬─────────────────────────────────────────────────────────┐
   │ regulatory_cite     │ verbatim citation (e.g. "31 CFR §1010.230(d)(1)")        │
   │ atomic_predicate    │ ONE sentence: "When X holds, the platform must Y."       │
   │ slug                │ snake_case, picked from the predicate                    │
   │ rule_type           │ onboarding | transaction-screening                        │
   │ verdict             │ accepted | rejected | held + rejected_rule string         │
   │ schema_needs        │ fields/tables that must exist in payload.ex BEFORE draft  │
   └─────────────────────┴─────────────────────────────────────────────────────────┘
```

### regulatory_cite

Verbatim. Include the regime root (BSA, OFAC, FFIEC, FinCEN, GENIUS Act, EU, FATF) and the section identifier exactly as written. Cite multiple if the snippet spans regimes — they go into the rule's `_description` and the corpus's `_label.cite`.

### atomic_predicate

One sentence in active voice. **No conjunctions** ("and", "or") if the snippet implies multiple atomic predicates — split them into separate scenarios. The skill ships ONE slice per invocation.

Examples:
- ✅ "When the AH's `country_of_residence` is on OFAC E.O. 13466 (North Korea), the platform must BLOCK outbound payments and emit an OFAC report."
- ❌ "The platform must screen senders and recipients, and block any party in a sanctioned country, and emit reports." (three predicates — three invocations)

### slug

Same rules as `references/use-cases-row-format.md`. Derived from the atomic predicate, not the citation.

### rule_type

Same classifier as `use-cases-row-format.md`:
- decision about the *entity* → `onboarding`
- decision about *this movement* → `transaction-screening`

### verdict

Map the regulatory requirement to the result vocabulary:

```
   Regulatory phrasing                   → verdict
   "prohibit", "must not process"        → rejected (block) + rejected_rule
   "block and report"                    → rejected (block + ofac_report) + rejected_rule
   "freeze", "hold pending"              → rejected (held) + rejected_rule
   "subject to review", "EDD"            → rejected (held) + rejected_rule
   "file a SAR"                          → rejected (held, sar-eligible) + rejected_rule
   "must screen but proceed if clean"    → accepted (with screening trace)
```

Pick the `rejected_rule` string up front — it must match between the JDM band's identifier and the corpus `_expected.rejected_rule`.

### schema_needs

Walk the predicate's named fields and check `references/payload-schema.md`. List any field/table not yet present. The skill MUST stop and route schema adds through the failing-test-first migration loop BEFORE drafting JDM.

---

## PDF reading

The skill reads PDFs via the `Read` tool with `pages: "N-M"`. For PDFs over 10 pages, pass the page range that contains the relevant clause; never read the whole document blindly.

```
   Read({ file_path: ".../genius-act.pdf", pages: "12-14" })
```

If the snippet spans multiple clauses, ask the user to identify the clause-of-record by section ID (e.g. "§4(a)(5)" not "the part about stablecoins").

---

## Worked example

Input file: `docs/regs/ofac-e-o-13466.txt`

Relevant clause:

> No U.S. person may engage in any transaction or dealing in or related to … the property and interests in property of the Government of North Korea, including any agency, instrumentality, or controlled entity thereof, or any person determined by the Secretary of the Treasury to be acting on behalf of, or owned or controlled by, the Government of North Korea.

Derived:

```
   regulatory_cite   = Executive Order 13466 (June 26, 2008)
   atomic_predicate  = When an AH's country_of_residence is "KP", the platform must BLOCK
                       outbound payments and emit an OFAC report.
   slug              = ah_country_kp_residence
   rule_type         = onboarding
   verdict           = rejected (block + ofac_report), rejected_rule = "ah_country_kp_residence"
   schema_needs      = legal_entities.country_of_residence  (ISO-3166-1)
                       legal_entities.sanctions_match       (jsonb)
                       legal_entities.sdn_list_entry_id     (string)
```

The skill then asks: "Confirm `(ah_country_kp_residence, onboarding, BLOCK)` — proceed?" before drafting.
