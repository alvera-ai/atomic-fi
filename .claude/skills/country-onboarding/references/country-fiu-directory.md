# Country FIU Directory

Reference for finding AML/CFT regulations per country. Not exhaustive — research further when onboarding a specific country.

## How to find a country's AML regulations

1. **Identify the FIU** — every FATF member has a Financial Intelligence Unit
2. **Find the central bank AML regs** — CTR thresholds, CDD requirements
3. **Check OpenSanctions** — `https://data.opensanctions.org/datasets/latest/index.json`, filter by country code prefix
4. **Check FATF mutual evaluation** — `https://www.fatf-gafi.org/en/countries.html` → country page → mutual evaluation report

## Common patterns across all jurisdictions

Every country with FATF membership has these minimum requirements:

| Requirement | What to look for | Schema fields |
|---|---|---|
| CTR threshold | Cash transaction reporting amount | `amount`, `currency` |
| STR/SAR filing | Suspicious transaction triggers | `amount`, velocity patterns |
| CDD/KYC | Customer identification | `kyc_status`, `legal_entity.*` |
| Sanctions screening | Domestic designated persons | Watchman search |
| PEP screening | Politically exposed persons | `politically_exposed_person` |
| Beneficial ownership | BO identification for entities | `beneficial_owners` |

## Selected countries (examples)

### US (United States)
- **FIU:** FinCEN (Financial Crimes Enforcement Network)
- **CTR threshold:** $10,000 (31 USC §5313)
- **Regs:** BSA (31 USC §5311-5336), OFAC sanctions, FinCEN guidance
- **OpenSanctions:** `us_ofac_sdn` (built into Watchman natively)

### AE (United Arab Emirates)
- **FIU:** CBUAE Financial Intelligence Unit
- **CTR threshold:** AED 55,000 (~$15,000)
- **Regs:** Federal Decree-Law No. 20/2018, CBUAE AML-CFT Guidance
- **OpenSanctions:** `ae_local_terrorists` (771 entities)

### IN (India)
- **FIU:** FIU-IND (under Ministry of Finance)
- **CTR threshold:** INR 10,00,000 (~$12,000)
- **Regs:** PMLA 2002, RBI KYC Master Direction 2016
- **OpenSanctions:** `in_mha_banned` (260 orgs)

### FR (France)
- **FIU:** TRACFIN (Traitement du Renseignement et Action contre les Circuits Financiers Clandestins)
- **CTR threshold:** EUR 10,000
- **Regs:** Code monétaire et financier (L.561-1 to L.561-50)
- **OpenSanctions:** `fr_tresor_gels_avoir` (12,474 entities), `fr_amf_regulatory_sanctions` (834)

### ID (Indonesia)
- **FIU:** PPATK (Pusat Pelaporan dan Analisis Transaksi Keuangan)
- **CTR threshold:** IDR 500,000,000 (~$31,000)
- **Regs:** OJK Regulation 12/POJK.01/2017
- **OpenSanctions:** `id_dttot` (1,074 entities)

### GB (United Kingdom)
- **FIU:** NCA UKFIU (National Crime Agency)
- **CTR threshold:** No fixed threshold (risk-based approach)
- **Regs:** MLR 2017, Proceeds of Crime Act 2002, Sanctions and Anti-Money Laundering Act 2018
- **OpenSanctions:** `gb_fcdo_sanctions` (18,136 entities)

### SG (Singapore)
- **FIU:** STRO (Suspicious Transaction Reporting Office)
- **CTR threshold:** SGD 20,000 (~$15,000)
- **Regs:** CDSA, MAS Notice 626/824
- **OpenSanctions:** Check index for `sg_` prefix

### JP (Japan)
- **FIU:** JAFIC (Japan Financial Intelligence Center)
- **CTR threshold:** JPY 2,000,000 (~$13,000)
- **Regs:** Act on Prevention of Transfer of Criminal Proceeds
- **OpenSanctions:** Check index for `jp_` prefix
