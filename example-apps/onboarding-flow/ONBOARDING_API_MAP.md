# Onboarding Flow → atomic-fi API Mapping

Reference for issue [#33](https://github.com/alvera-ai/atomic-fi/issues/33).

**TypeScript API schemas:** [`src/features/onboarding/api-schemas.ts`](src/features/onboarding/api-schemas.ts) — Request/Response types that mirror the Elixir Ecto schemas 1:1.

---

## API Call Sequence

### M1: AccountHolder end-to-end

Upload PDF → doc-ai extracts → form fills → Submit triggers:

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. POST /api/legal-entities                                     │
│    Create LegalEntity with PII (name, dob, addresses, IDs)      │
│    Returns: legal_entity_id                                     │
├─────────────────────────────────────────────────────────────────┤
│ 2. POST /api/account-holders                                    │
│    Create AccountHolder linked to legal_entity_id               │
│    Sets: holder_type, enabled_currencies, enabled_regimes       │
│    Returns: account_holder_id                                   │
│    Side-effect: creates Ledger + LedgerAccounts, triggers       │
│    OnboardingContext.onboard (screening → engine → controls)    │
├─────────────────────────────────────────────────────────────────┤
│ 3. POST /api/documents                                          │
│    Upload Document metadata linked to account_holder_id         │
│    Sets: document_type, name, status, file metadata             │
│    Returns: document_id                                         │
├─────────────────────────────────────────────────────────────────┤
│ 4. POST /api/kyc-requirements                                   │
│    Create KycRequirement linked to AH + LE + Document           │
│    Sets: scope=account_holder, requirement_type, status          │
│    Returns: kyc_requirement_id                                  │
└─────────────────────────────────────────────────────────────────┘
```

### M2: Counterparty end-to-end

Same PDF or separate doc → extract counterparty fields → Submit:

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. POST /api/legal-entities                                     │
│    Create LegalEntity for the counterparty (external party PII) │
│    Returns: legal_entity_id                                     │
├─────────────────────────────────────────────────────────────────┤
│ 2. POST /api/counterparties                                     │
│    Create Counterparty linked to account_holder_id +             │
│    legal_entity_id                                              │
│    Sets: status, enabled_regimes                                │
│    Returns: counterparty_id                                     │
│    Side-effect: ensures CP LedgerAccounts, triggers onboarding  │
├─────────────────────────────────────────────────────────────────┤
│ 3. POST /api/kyc-requirements                                   │
│    scope=counterparty, linked to AH + CP's LE                   │
│    Returns: kyc_requirement_id                                  │
└─────────────────────────────────────────────────────────────────┘
```

### M3: PaymentAccount end-to-end

Gated: AccountHolder must have KycRequirement{scope: account_holder, status: approved}.

```
┌─────────────────────────────────────────────────────────────────┐
│ 0. GET /api/kyc-requirements?account_holder_id=X&scope=         │
│    account_holder                                               │
│    Check: status == approved → enable Submit button             │
├─────────────────────────────────────────────────────────────────┤
│ 1. POST /api/payment-accounts                                   │
│    Create PaymentAccount linked to account_holder_id            │
│    Sets: account_type, currency, routing/account numbers        │
│    Returns: payment_account_id                                  │
│    Side-effect: ensures PA LedgerAccounts (block-by-default)    │
├─────────────────────────────────────────────────────────────────┤
│ 2. POST /api/kyc-requirements                                   │
│    scope=payment_account, linked to AH + AH's LE               │
│    Returns: kyc_requirement_id                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Field Mapping: Frontend → Backend

### AccountHolder + LegalEntity

| Frontend Field (`onboarding.ts`) | Backend Field | API | Notes |
|---|---|---|---|
| `business_profile.legal_name` | `business_name` | `LegalEntity` | Direct rename |
| `business_profile.trade_name` | `doing_business_as_names[]` | `LegalEntity` | String → array |
| `business_profile.entity_type` | `holder_type` | `AccountHolder` | Enum: individual / business / trust / nonprofit |
| `business_profile.incorporation_date` | `date_formed` | `LegalEntity` | Direct rename |
| `business_profile.jurisdiction` | `citizenship_country` | `LegalEntity` | ISO 3166-1 alpha-2 |
| `business_profile.license_number` | — | — | No backend field. Store as `Document` or `LegalEntity.metadata` |
| `business_profile.license_expiry` | — | — | No backend field |
| `addresses[].line1, city, country...` | `addresses[].line1, city, country...` | `LegalEntity` (nested) | Types differ: frontend has `REGISTERED / OPERATING / CORRESPONDENCE`, backend uses LegalEntityAddress |
| `addresses[].emirate` | `addresses[].region` | `LegalEntity` | Rename |
| `business_contacts[]` | — | — | **No backend entity.** Not in scope |
| `business_activity.primary_activity` | — | — | **No backend entity.** Could use AH metadata |
| `business_activity.source_of_funds` | — | — | **No backend entity** |
| `transfer_behavior.*` | — | — | **No backend entity.** `AccountActivitySnapshot` is read-only analytics, not input |
| `ownership_structure.*` | — | — | **No backend entity** |

### Directors / Signatories / UBOs → BeneficialOwner

| Frontend Field | Backend Field | API | Notes |
|---|---|---|---|
| `directors[].full_name` | `first_name + last_name` | `LegalEntity` (for the director) | Need to split name |
| `directors[].nationality` | `citizenship_country` | `LegalEntity` | ISO 3166-1 |
| `directors[].date_of_birth` | `date_of_birth` | `LegalEntity` | Direct |
| `directors[].passport_number` | `identifications[].number` | `LegalEntity` (nested) | `identification_type: passport` |
| `directors[].is_signatory` | — | — | No backend concept |
| `signatories[]` | — | — | **No backend entity** |
| `ubos[].full_name` | `first_name + last_name` | `LegalEntity` (for the UBO) | Split name |
| `ubos[].ownership_percentage` | `ownership_pct` | `BeneficialOwner` | Direct |
| `ubos[].nationality` | `citizenship_country` | `LegalEntity` | ISO 3166-1 |
| `ubos[].date_of_birth` | `date_of_birth` | `LegalEntity` | Direct |
| `ubos[].passport_number` | `identifications[].number` | `LegalEntity` (nested) | `identification_type: passport` |
| — | `control_type` | `BeneficialOwner` | **Missing from frontend.** Enum: shareholder / director / officer / trustee |

### Documents

| Frontend Field | Backend Field | API | Notes |
|---|---|---|---|
| `documents[].file_id` | `id` | `Document` | Server-generated |
| `documents[].doc_type` | `document_type` | `Document` | Enum values differ — see below |
| `documents[].filename` | `file_name` | `Document` | Direct |
| `documents[].status` | `status` | `Document` | Enum values differ — see below |
| — | `file_key` | `Document` | **Missing.** S3/R2 storage path |
| — | `file_size` | `Document` | **Missing.** Bytes |
| — | `content_type` | `Document` | **Missing.** MIME type |
| — | `primary` | `Document` | **Missing.** Boolean, enforced by DB trigger |
| — | `name` | `Document` | **Missing.** Template name (e.g. "kyc_passport") |
| — | `account_holder_id` | `Document` | **Missing.** FK to AccountHolder |

#### Document Type Enum Mapping

| Frontend | Backend |
|---|---|
| `TRADE_LICENSE` | `business_registration` |
| `MEMORANDUM_OF_ASSOCIATION` | `business_registration` |
| `CERTIFICATE_OF_INCORPORATION` | `business_registration` |
| `PASSPORT` | `identity_document` |
| `EMIRATES_ID` | `identity_document` |
| `PROOF_OF_ADDRESS` | `proof_of_address` |
| `BANK_STATEMENT` | `source_of_funds` |
| `OTHER` | `other` |

---

## What Backend Supports That Frontend Doesn't Cover

| Backend Entity | Endpoint | Status |
|---|---|---|
| `Counterparty` | `POST /api/counterparties` | Not in frontend |
| `PaymentAccount` | `POST /api/payment-accounts` | Not in frontend |
| `KycRequirement` | `POST /api/kyc-requirements` | Not in frontend |
| `ComplianceScreening` | `POST /api/compliance-screenings/screen-*` | Not in frontend (auto-triggered on AH create) |
| `LegalEntity.identifications[]` | Nested in `POST /api/legal-entities` | Frontend has flat passport_number, not structured |
| `LegalEntity.phone_numbers[]` | Nested in `POST /api/legal-entities` | Frontend has phone as flat string |
| `AccountHolder.enabled_currencies` | `POST /api/account-holders` | Not in frontend |
| `AccountHolder.enabled_regimes` | `POST /api/account-holders` | Not in frontend |
| `BeneficialOwner.control_type` | `POST /api/beneficial-owners` | Not in frontend |

---

## Summary

**~40% of the current frontend types map to backend schemas.** The remaining ~60% (business contacts, activity, transfer behavior, ownership structure, directors, signatories) have no backend home.

For issue #33, the frontend types need to be restructured to mirror the actual API request schemas: `AccountHolderRequest`, `LegalEntityRequest`, `DocumentRequest`, `KycRequirementRequest`, `BeneficialOwnerRequest`, `CounterpartyRequest`, `PaymentAccountRequest`.
