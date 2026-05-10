import type {
  AccountHolderResponse,
  ApiInfoResponse,
  ApiKeyResponse,
  BeneficialOwnerResponse,
  ComplianceScreeningResponse,
  CounterpartyResponse,
  DocumentResponse,
  KycRequirementResponse,
  LedgerAccountBalanceResponse,
  LedgerEntryResponse,
  Recommendation,
  SanctionsMatchResponse,
  TenantResponse,
  TransactionResponse,
  TransactionStatus,
  TransactionType,
} from "@/api/types";

const TENANT = "11111111-1111-1111-1111-111111111111";

const uid = (n: number) => `${n.toString(16).padStart(8, "0")}-aaaa-bbbb-cccc-${n.toString(16).padStart(12, "0")}`;
const iso = (d: Date) => d.toISOString();
const today = new Date("2026-05-02T12:00:00Z");
const daysAgo = (n: number) => new Date(today.getTime() - n * 86_400_000);

// ───── Account holders
export const accountHolders: AccountHolderResponse[] = [
  { id: uid(101), display_name: "Acme Robotics", legal_name: "Acme Robotics LLC", entity_type: "business", country: "US", kyc_status: "approved", risk_level: "low", email: "ops@acme.io", inserted_at: iso(daysAgo(120)), updated_at: iso(daysAgo(2)), tenant_id: TENANT },
  { id: uid(102), display_name: "Lumière Studio", legal_name: "Lumière Studio SARL", entity_type: "business", country: "FR", kyc_status: "not_started", risk_level: "low", email: "finance@lumiere.fr", inserted_at: iso(daysAgo(1)), updated_at: iso(daysAgo(1)), tenant_id: TENANT },
  { id: uid(103), display_name: "Nordic Freight AB", legal_name: "Nordic Freight Aktiebolag", entity_type: "business", country: "SE", kyc_status: "in_progress", risk_level: "high", email: "kyc@nordicfreight.se", inserted_at: iso(daysAgo(6)), updated_at: iso(daysAgo(1)), tenant_id: TENANT },
  { id: uid(104), display_name: "Jin Wei", legal_name: "Jin Wei", entity_type: "individual", country: "CN", kyc_status: "approved", risk_level: "low", email: "jin.wei@example.com", inserted_at: iso(daysAgo(1)), updated_at: iso(daysAgo(1)), tenant_id: TENANT },
  { id: uid(105), display_name: "Cairo Trade Co", legal_name: "Cairo Trade Co", entity_type: "business", country: "EG", kyc_status: "in_progress", risk_level: "high", email: "ops@cairotrade.eg", inserted_at: iso(daysAgo(8)), updated_at: iso(daysAgo(3)), tenant_id: TENANT },
  { id: uid(106), display_name: "Helios Energy", legal_name: "Helios Energy GmbH", entity_type: "business", country: "DE", kyc_status: "approved", risk_level: "low", email: "treasury@helios.de", inserted_at: iso(daysAgo(200)), updated_at: iso(daysAgo(15)), tenant_id: TENANT },
  { id: uid(107), display_name: "Maria González", legal_name: "Maria González", entity_type: "individual", country: "MX", kyc_status: "in_progress", risk_level: "medium", email: "maria.gonzalez@example.com", inserted_at: iso(daysAgo(2)), updated_at: iso(daysAgo(1)), tenant_id: TENANT },
  { id: uid(108), display_name: "Tokyo Cloud KK", legal_name: "Tokyo Cloud Kabushiki Kaisha", entity_type: "business", country: "JP", kyc_status: "approved", risk_level: "low", email: "billing@tokyocloud.jp", inserted_at: iso(daysAgo(180)), updated_at: iso(daysAgo(20)), tenant_id: TENANT },
  { id: uid(109), display_name: "Volga Trading LLC", legal_name: "Volga Trading LLC", entity_type: "business", country: "RU", kyc_status: "in_progress", risk_level: "critical", email: "ops@volgatrading.ru", inserted_at: iso(daysAgo(12)), updated_at: iso(daysAgo(2)), tenant_id: TENANT },
];

// ───── Counterparties
export const counterparties: CounterpartyResponse[] = [
  { id: uid(201), display_name: "Stripe Payments", legal_name: "Stripe Payments Inc.", country: "US", status: "active", external_reference: "stripe-001", tenant_id: TENANT, inserted_at: iso(daysAgo(400)), updated_at: iso(daysAgo(3)) },
  { id: uid(202), display_name: "AWS EMEA", legal_name: "Amazon Web Services EMEA SARL", country: "LU", status: "active", external_reference: null, tenant_id: TENANT, inserted_at: iso(daysAgo(400)), updated_at: iso(daysAgo(7)) },
  { id: uid(203), display_name: "ShadowBank Holdings", legal_name: "ShadowBank Holdings Ltd", country: "KY", status: "blocked", external_reference: null, tenant_id: TENANT, inserted_at: iso(daysAgo(40)), updated_at: iso(daysAgo(1)) },
  { id: uid(204), display_name: "Mediterranean Shipping", legal_name: "Mediterranean Shipping S.p.A.", country: "IT", status: "active", external_reference: "msc-9921", tenant_id: TENANT, inserted_at: iso(daysAgo(150)), updated_at: iso(daysAgo(10)) },
  { id: uid(205), display_name: "Volga Trading LLC", legal_name: "Volga Trading LLC", country: "RU", status: "under_review", external_reference: null, tenant_id: TENANT, inserted_at: iso(daysAgo(15)), updated_at: iso(daysAgo(2)) },
  { id: uid(206), display_name: "Coffee Co Roasters", legal_name: "Coffee Co Roasters", country: "ET", status: "active", external_reference: null, tenant_id: TENANT, inserted_at: iso(daysAgo(220)), updated_at: iso(daysAgo(30)) },
  { id: uid(207), display_name: "Banco Atlántico", legal_name: "Banco Atlántico S.A.", country: "PA", status: "suspended", external_reference: null, tenant_id: TENANT, inserted_at: iso(daysAgo(80)), updated_at: iso(daysAgo(4)) },
  { id: uid(208), display_name: "Heidelberg Werks", legal_name: "Heidelberg Werks AG", country: "DE", status: "active", external_reference: null, tenant_id: TENANT, inserted_at: iso(daysAgo(300)), updated_at: iso(daysAgo(12)) },
];

// ───── Beneficial owners (chains for a few counterparties)
export const beneficialOwners: BeneficialOwnerResponse[] = [
  { id: uid(301), counterparty_id: uid(203), full_name: "Igor Petrov", ownership_percentage: 55, country: "RU", is_pep: true, tenant_id: TENANT, inserted_at: iso(daysAgo(40)) },
  { id: uid(302), counterparty_id: uid(203), full_name: "Sergey Volkov", ownership_percentage: 30, country: "CY", is_pep: false, tenant_id: TENANT, inserted_at: iso(daysAgo(40)) },
  { id: uid(303), counterparty_id: uid(203), full_name: "Anonymous Trust #14", ownership_percentage: 15, country: "KY", is_pep: false, tenant_id: TENANT, inserted_at: iso(daysAgo(40)) },
  { id: uid(304), counterparty_id: uid(205), full_name: "Dmitri Sokolov", ownership_percentage: 80, country: "RU", is_pep: true, tenant_id: TENANT, inserted_at: iso(daysAgo(15)) },
  { id: uid(305), counterparty_id: uid(207), full_name: "Carlos Vega", ownership_percentage: 100, country: "PA", is_pep: false, tenant_id: TENANT, inserted_at: iso(daysAgo(80)) },
];

// ───── Documents
export const documents: DocumentResponse[] = [
  { id: uid(401), filename: "passport_jin_wei.pdf", document_type: "id_document", account_holder_id: uid(104), uploaded_at: iso(daysAgo(295)), size_bytes: 1_204_322, mime_type: "application/pdf" },
  { id: uid(402), filename: "utility_bill_acme.pdf", document_type: "proof_of_address", account_holder_id: uid(101), uploaded_at: iso(daysAgo(110)), size_bytes: 502_120, mime_type: "application/pdf" },
  { id: uid(403), filename: "articles_of_incorporation.pdf", document_type: "incorporation", account_holder_id: uid(103), uploaded_at: iso(daysAgo(18)), size_bytes: 880_122, mime_type: "application/pdf" },
  { id: uid(404), filename: "ubo_chart_cairotrade.png", document_type: "ownership_chart", account_holder_id: uid(105), uploaded_at: iso(daysAgo(58)), size_bytes: 411_902, mime_type: "image/png" },
];

// ───── KYC requirements
export const kycRequirements: KycRequirementResponse[] = [
  { id: uid(501), account_holder_id: uid(101), requirement_type: "proof_of_address", status: "approved", document_id: uid(402), notes: null, inserted_at: iso(daysAgo(110)), updated_at: iso(daysAgo(108)) },
  { id: uid(502), account_holder_id: uid(101), requirement_type: "tax_id", status: "approved", document_id: null, notes: "EIN verified", inserted_at: iso(daysAgo(110)), updated_at: iso(daysAgo(105)) },
  { id: uid(503), account_holder_id: uid(103), requirement_type: "incorporation", status: "submitted", document_id: uid(403), notes: "Awaiting review", inserted_at: iso(daysAgo(18)), updated_at: iso(daysAgo(2)) },
  { id: uid(504), account_holder_id: uid(103), requirement_type: "ubo_disclosure", status: "pending", document_id: null, notes: null, inserted_at: iso(daysAgo(18)), updated_at: iso(daysAgo(18)) },
  { id: uid(505), account_holder_id: uid(105), requirement_type: "enhanced_due_diligence", status: "pending", document_id: uid(404), notes: "High-risk jurisdiction", inserted_at: iso(daysAgo(58)), updated_at: iso(daysAgo(3)) },
  { id: uid(506), account_holder_id: uid(104), requirement_type: "id_document", status: "approved", document_id: uid(401), notes: null, inserted_at: iso(daysAgo(295)), updated_at: iso(daysAgo(290)) },
  { id: uid(507), account_holder_id: uid(107), requirement_type: "id_document", status: "rejected", document_id: null, notes: "Document expired", inserted_at: iso(daysAgo(10)), updated_at: iso(daysAgo(5)) },
];

// ───── Compliance screenings + sanctions matches
export const complianceScreenings: ComplianceScreeningResponse[] = [
  { id: uid(601), subject_type: "counterparty", subject_id: uid(203), status: "match", provider: "ComplyAdvantage", screened_at: iso(daysAgo(1)), reviewer: null },
  { id: uid(602), subject_type: "counterparty", subject_id: uid(205), status: "potential_match", provider: "Refinitiv", screened_at: iso(daysAgo(2)), reviewer: null },
  { id: uid(603), subject_type: "account_holder", subject_id: uid(105), status: "potential_match", provider: "ComplyAdvantage", screened_at: iso(daysAgo(3)), reviewer: "alex.officer@alvera.ai" },
  { id: uid(604), subject_type: "counterparty", subject_id: uid(201), status: "clear", provider: "ComplyAdvantage", screened_at: iso(daysAgo(7)), reviewer: null },
  { id: uid(605), subject_type: "counterparty", subject_id: uid(207), status: "review", provider: "Refinitiv", screened_at: iso(daysAgo(4)), reviewer: null },
];

export const sanctionsMatches: SanctionsMatchResponse[] = [
  { id: uid(701), compliance_screening_id: uid(601), matched_name: "ShadowBank Holdings Ltd", list_name: "OFAC SDN", score: 96, false_positive_qualifier: null, reviewer: null, justification: null },
  { id: uid(702), compliance_screening_id: uid(602), matched_name: "Volga Trading", list_name: "EU CFSP", score: 78, false_positive_qualifier: null, reviewer: null, justification: null },
  { id: uid(703), compliance_screening_id: uid(603), matched_name: "Cairo Trade", list_name: "UN Consolidated", score: 64, false_positive_qualifier: "name_collision", reviewer: "alex.officer@alvera.ai", justification: "Different entity, country, and DOB." },
  { id: uid(704), compliance_screening_id: uid(605), matched_name: "Banco Atlántico", list_name: "OFAC SDN", score: 71, false_positive_qualifier: null, reviewer: null, justification: null },
];

// ───── Transactions (~28 with rich linkage)
type TxSeed = {
  i: number;
  type: TransactionType;
  status: TransactionStatus;
  amount: number;
  currency: string;
  daysAgo: number;
  holder: number;
  creditorCp?: number;
  debtorCp?: number;
  screening?: number;
};
const TX_SEEDS: TxSeed[] = [
  { i: 1, type: "credit_transfer", status: "settled", amount: 1_250_000, currency: "USD", daysAgo: 1, holder: 101, creditorCp: 201 },
  { i: 2, type: "credit_transfer", status: "rejected", amount: 8_400_000, currency: "USD", daysAgo: 1, holder: 105, creditorCp: 203, screening: 601 },
  { i: 3, type: "card_payment", status: "settled", amount: 4_999, currency: "EUR", daysAgo: 0, holder: 102, creditorCp: 202 },
  { i: 4, type: "direct_debit", status: "pending", amount: 89_000, currency: "EUR", daysAgo: 0, holder: 102, creditorCp: 202 },
  { i: 5, type: "credit_transfer", status: "pending", amount: 12_000_000, currency: "USD", daysAgo: 2, holder: 103, creditorCp: 205, screening: 602 },
  { i: 6, type: "credit_transfer", status: "settled", amount: 350_000, currency: "GBP", daysAgo: 3, holder: 106, creditorCp: 208 },
  { i: 7, type: "internal_transfer", status: "settled", amount: 50_000_000, currency: "USD", daysAgo: 4, holder: 101 },
  { i: 8, type: "card_payment", status: "rejected", amount: 32_500, currency: "USD", daysAgo: 1, holder: 107, creditorCp: 201 },
  { i: 9, type: "credit_transfer", status: "accepted", amount: 4_200_000, currency: "USD", daysAgo: 0, holder: 105, creditorCp: 207, screening: 605 },
  { i: 10, type: "refund", status: "settled", amount: 4_999, currency: "EUR", daysAgo: 5, holder: 102, debtorCp: 202 },
  { i: 11, type: "credit_transfer", status: "settled", amount: 980_000, currency: "USD", daysAgo: 6, holder: 104, creditorCp: 206 },
  { i: 12, type: "direct_debit", status: "settled", amount: 199_000, currency: "GBP", daysAgo: 7, holder: 106, creditorCp: 208 },
  { i: 13, type: "credit_transfer", status: "reversed", amount: 670_000, currency: "USD", daysAgo: 8, holder: 101, creditorCp: 204 },
  { i: 14, type: "card_payment", status: "settled", amount: 14_500, currency: "JPY", daysAgo: 2, holder: 108, creditorCp: 202 },
  { i: 15, type: "credit_transfer", status: "cancelled", amount: 5_000_000, currency: "USD", daysAgo: 9, holder: 103, creditorCp: 204 },
  { i: 16, type: "credit_transfer", status: "settled", amount: 220_000, currency: "EUR", daysAgo: 10, holder: 102, creditorCp: 208 },
  { i: 17, type: "credit_transfer", status: "pending", amount: 9_900_000, currency: "USD", daysAgo: 0, holder: 105, creditorCp: 203, screening: 601 },
  { i: 18, type: "internal_transfer", status: "settled", amount: 25_000_000, currency: "USD", daysAgo: 11, holder: 106 },
  { i: 19, type: "card_payment", status: "settled", amount: 7_499, currency: "GBP", daysAgo: 12, holder: 106, creditorCp: 201 },
  { i: 20, type: "credit_transfer", status: "settled", amount: 145_000, currency: "USD", daysAgo: 13, holder: 104, creditorCp: 206 },
  { i: 21, type: "direct_debit", status: "rejected", amount: 89_000, currency: "EUR", daysAgo: 14, holder: 102, creditorCp: 208 },
  { i: 22, type: "credit_transfer", status: "settled", amount: 3_300_000, currency: "USD", daysAgo: 15, holder: 101, creditorCp: 204 },
  { i: 23, type: "credit_transfer", status: "pending", amount: 1_750_000, currency: "USD", daysAgo: 1, holder: 103, creditorCp: 205, screening: 602 },
  { i: 24, type: "refund", status: "settled", amount: 32_500, currency: "USD", daysAgo: 16, holder: 107, debtorCp: 201 },
  { i: 25, type: "credit_transfer", status: "settled", amount: 540_000, currency: "USD", daysAgo: 17, holder: 108, creditorCp: 202 },
  { i: 26, type: "card_payment", status: "settled", amount: 12_900, currency: "USD", daysAgo: 18, holder: 101, creditorCp: 201 },
  { i: 27, type: "credit_transfer", status: "rejected", amount: 6_700_000, currency: "USD", daysAgo: 2, holder: 105, creditorCp: 207, screening: 605 },
  { i: 28, type: "credit_transfer", status: "settled", amount: 1_100_000, currency: "EUR", daysAgo: 19, holder: 106, creditorCp: 208 },
];

export const transactions: TransactionResponse[] = TX_SEEDS.map((s) => {
  const date = daysAgo(s.daysAgo);
  return {
    id: uid(1000 + s.i),
    transaction_type: s.type,
    status: s.status,
    amount: s.amount,
    currency: s.currency,
    end_to_end_id: `E2E-${(2026000 + s.i).toString()}`,
    uetr: `${uid(9000 + s.i)}`,
    instruction_id: `INSTR-${s.i.toString().padStart(5, "0")}`,
    status_reason_code: s.status === "rejected" ? "RJCT" : s.status === "accepted" ? "ACCP" : s.status === "settled" ? "ACSC" : s.status === "pending" ? "PDNG" : null,
    requested_execution_date: iso(date).slice(0, 10),
    settlement_date: s.status === "settled" || s.status === "reversed" ? iso(date).slice(0, 10) : null,
    transaction_external_id: `EXT-${s.i.toString().padStart(6, "0")}`,
    account_holder_id: uid(s.holder),
    debtor_payment_account_id: uid(8000 + s.holder),
    creditor_payment_account_id: s.creditorCp ? uid(8000 + s.creditorCp) : null,
    debtor_counterparty_id: s.debtorCp ? uid(s.debtorCp) : null,
    creditor_counterparty_id: s.creditorCp ? uid(s.creditorCp) : null,
    ledger_entry_id: uid(2000 + s.i),
    compliance_screening_id: s.screening ? uid(s.screening) : null,
    tenant_id: TENANT,
    inserted_at: iso(date),
    updated_at: iso(date),
  };
});

// ───── Ledger entries + balances
export const ledgerEntries: LedgerEntryResponse[] = transactions.map((t, i) => ({
  id: t.ledger_entry_id!,
  transaction_id: t.id,
  ledger_account_id: uid(3000 + (i % 5)),
  direction: t.transaction_type === "refund" ? "credit" : "debit",
  amount: t.amount,
  currency: t.currency,
  posted_at: t.inserted_at,
}));

export const ledgerAccountBalances: LedgerAccountBalanceResponse[] = [
  { id: uid(3100), ledger_account_id: uid(3000), account_label: "Operating USD", balance: 84_500_000, currency: "USD", as_of: iso(today) },
  { id: uid(3101), ledger_account_id: uid(3001), account_label: "Operating EUR", balance: 12_400_000, currency: "EUR", as_of: iso(today) },
  { id: uid(3102), ledger_account_id: uid(3002), account_label: "Operating GBP", balance: 3_900_000, currency: "GBP", as_of: iso(today) },
  { id: uid(3103), ledger_account_id: uid(3003), account_label: "Reserve USD", balance: 25_000_000, currency: "USD", as_of: iso(today) },
  { id: uid(3104), ledger_account_id: uid(3004), account_label: "JPY Settlement", balance: 8_900_000, currency: "JPY", as_of: iso(today) },
];

// ───── Tenants
export const tenants: TenantResponse[] = [
  { id: TENANT, name: "Acme Corp · Sandbox", slug: "acme-sandbox", region: "us-east-1", blocklist_refreshed_at: iso(daysAgo(0)), inserted_at: iso(daysAgo(120)) },
  { id: uid(11), name: "Acme Corp · Production", slug: "acme-prod", region: "us-east-1", blocklist_refreshed_at: iso(daysAgo(1)), inserted_at: iso(daysAgo(120)) },
  { id: uid(12), name: "Lumière Studio", slug: "lumiere", region: "eu-west-1", blocklist_refreshed_at: iso(daysAgo(3)), inserted_at: iso(daysAgo(40)) },
];

// ───── API keys
export const apiKeys: ApiKeyResponse[] = [
  { id: uid(901), name: "ops-dashboard", customer_id: null, role_id: uid(800), tenant_id: TENANT, inserted_at: iso(daysAgo(40)), last_used_at: iso(daysAgo(0)) },
  { id: uid(902), name: "platform-agent", customer_id: null, role_id: uid(801), tenant_id: TENANT, inserted_at: iso(daysAgo(60)), last_used_at: iso(daysAgo(2)) },
  { id: uid(903), name: "etl-readonly", customer_id: null, role_id: uid(802), tenant_id: TENANT, inserted_at: iso(daysAgo(90)), last_used_at: iso(daysAgo(7)) },
];

// ───── API info
export const apiInfo: ApiInfoResponse = {
  version: "2026.04.18",
  build: "atomicfi-api@a91c4f2",
  database_status: "ok",
  uptime_seconds: 3 * 86_400 + 11 * 3_600,
  release_channel: "stable",
};

// ───── Recommendations (from the alvera-ai/platform mock stream)
export const recommendations: Recommendation[] = [
  {
    id: uid(1101),
    kind: "add_blocklist_entry",
    subject_type: "counterparty",
    subject_id: uid(203),
    subject_label: "ShadowBank Holdings",
    signal: "OFAC SDN delta · 2 hrs ago",
    rationale: "Newly designated entity matched at 96% on legal name and country.",
    confidence: 0.97,
    created_at: iso(daysAgo(0)),
    status: "open",
    payload: { list: "OFAC_SDN", reason: "Sanctions match" },
  },
  {
    id: uid(1102),
    kind: "raise_risk_classification",
    subject_type: "account_holder",
    subject_id: uid(105),
    subject_label: "Cairo Trade Co",
    signal: "Adverse media · Reuters",
    rationale: "Three independent reports of trade-finance fraud in the past 30 days.",
    confidence: 0.82,
    created_at: iso(daysAgo(0)),
    status: "open",
    payload: { from: "high", to: "prohibited" },
  },
  {
    id: uid(1103),
    kind: "request_kyc_document",
    subject_type: "account_holder",
    subject_id: uid(103),
    subject_label: "Nordic Freight AB",
    signal: "Onboarding stalled 14d",
    rationale: "UBO disclosure outstanding past internal SLA. Auto-request a fresh upload.",
    confidence: 0.74,
    created_at: iso(daysAgo(1)),
    status: "open",
    payload: { requirement_type: "ubo_disclosure" },
  },
  {
    id: uid(1104),
    kind: "suspend_counterparty",
    subject_type: "counterparty",
    subject_id: uid(207),
    subject_label: "Banco Atlántico",
    signal: "Regulatory action · OCC",
    rationale: "OCC cease-and-desist published this morning. Suspend pending review.",
    confidence: 0.88,
    created_at: iso(daysAgo(0)),
    status: "open",
    payload: { status: "suspended" },
  },
  {
    id: uid(1105),
    kind: "raise_risk_classification",
    subject_type: "account_holder",
    subject_id: uid(107),
    subject_label: "Maria González",
    signal: "KYC document rejected",
    rationale: "Pattern of expired ID submissions across two onboarding attempts.",
    confidence: 0.66,
    created_at: iso(daysAgo(2)),
    status: "open",
    payload: { from: "high", to: "prohibited" },
  },
];

// ───── Helpers
export const TENANT_ID = TENANT;
