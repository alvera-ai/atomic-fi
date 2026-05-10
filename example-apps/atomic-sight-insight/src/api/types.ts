// Types mirror AtomicFi OpenAPI schemas (atomicfi-openapi.yaml).
// Field names + enums kept exact so the rewire to @atomic-fi/sdk is a one-line swap.

export type UUID = string;

export type TransactionStatus =
  | "pending" | "accepted" | "settled" | "rejected" | "reversed" | "cancelled";

export type TransactionType =
  | "credit_transfer" | "direct_debit" | "card_payment" | "refund" | "reversal" | "internal_transfer";

export interface TransactionResponse {
  id: UUID;
  transaction_type: TransactionType;
  status: TransactionStatus | null;
  amount: number;
  currency: string;
  end_to_end_id: string | null;
  uetr: string | null;
  instruction_id: string | null;
  status_reason_code: string | null;
  requested_execution_date: string | null;
  settlement_date: string | null;
  transaction_external_id: string | null;
  account_holder_id: UUID;
  debtor_payment_account_id: UUID | null;
  creditor_payment_account_id: UUID | null;
  debtor_counterparty_id: UUID | null;
  creditor_counterparty_id: UUID | null;
  ledger_entry_id: UUID | null;
  compliance_screening_id: UUID | null;
  tenant_id: UUID;
  inserted_at: string;
  updated_at: string;
}

export type KycStatus = "not_started" | "in_progress" | "approved" | "rejected" | "on_hold";
export type RiskLevel = "low" | "medium" | "high" | "critical" | "prohibited";

export interface AccountHolderResponse {
  id: UUID;
  display_name: string;
  legal_name: string;
  entity_type: "individual" | "business";
  country: string;
  kyc_status: KycStatus;
  risk_level: RiskLevel;
  email: string | null;
  inserted_at: string;
  updated_at: string;
  tenant_id: UUID;
}

export type CounterpartyStatus = "active" | "blocked" | "under_review" | "suspended";

export interface CounterpartyResponse {
  id: UUID;
  display_name: string;
  legal_name: string;
  country: string;
  status: CounterpartyStatus;
  external_reference: string | null;
  tenant_id: UUID;
  inserted_at: string;
  updated_at: string;
}

export interface BeneficialOwnerResponse {
  id: UUID;
  counterparty_id: UUID;
  full_name: string;
  ownership_percentage: number;
  country: string;
  is_pep: boolean;
  tenant_id: UUID;
  inserted_at: string;
}

export type KycRequirementStatus = "pending" | "submitted" | "approved" | "rejected" | "waived";

export interface KycRequirementResponse {
  id: UUID;
  account_holder_id: UUID;
  requirement_type: string;
  status: KycRequirementStatus;
  document_id: UUID | null;
  notes: string | null;
  inserted_at: string;
  updated_at: string;
}

export interface DocumentResponse {
  id: UUID;
  filename: string;
  document_type: string;
  account_holder_id: UUID | null;
  uploaded_at: string;
  size_bytes: number;
  mime_type: string;
}

export type ScreeningStatus = "clear" | "potential_match" | "match" | "review";

export interface ComplianceScreeningResponse {
  id: UUID;
  subject_type: "account_holder" | "counterparty" | "beneficial_owner";
  subject_id: UUID;
  status: ScreeningStatus;
  provider: string;
  screened_at: string;
  reviewer: string | null;
}

export interface SanctionsMatchResponse {
  id: UUID;
  compliance_screening_id: UUID;
  matched_name: string;
  list_name: string;
  score: number;
  false_positive_qualifier: string | null;
  reviewer: string | null;
  justification: string | null;
}

export interface LedgerEntryResponse {
  id: UUID;
  transaction_id: UUID;
  ledger_account_id: UUID;
  direction: "debit" | "credit";
  amount: number;
  currency: string;
  posted_at: string;
}

export interface LedgerAccountBalanceResponse {
  id: UUID;
  ledger_account_id: UUID;
  account_label: string;
  balance: number;
  currency: string;
  as_of: string;
}

// ───── Engineer / platform
export interface ApiKeyResponse {
  id: UUID;
  name: string;
  customer_id: UUID | null;
  role_id: UUID;
  tenant_id: UUID;
  inserted_at: string;
  last_used_at: string | null;
  raw_key?: string; // returned only on create
}

export interface TenantResponse {
  id: UUID;
  name: string;
  slug: string;
  region: string;
  blocklist_refreshed_at: string | null;
  inserted_at: string;
}

export interface ApiInfoResponse {
  version: string;
  build: string;
  database_status: "ok" | "degraded" | "down";
  uptime_seconds: number;
  release_channel: string;
}

// ───── Rules engine
export type RuleScope = "transaction" | "account_holder";
export type RuleStatus = "sandbox" | "live" | "archived";
export type RuleSeverity = "low" | "medium" | "high" | "critical";
export type RuleAction = "flag" | "review" | "block";

export type RuleOperator =
  | "eq" | "neq" | "in" | "not_in"
  | "gt" | "gte" | "lt" | "lte"
  | "between" | "contains" | "exists";

export interface RuleCondition {
  id: string;
  kind: "condition";
  field: string;
  operator: RuleOperator;
  value: unknown;
  weight: number; // 1-10
}

export interface RuleConditionGroup {
  id: string;
  kind: "group";
  combinator: "AND" | "OR";
  children: RuleNode[];
}

export type RuleNode = RuleCondition | RuleConditionGroup;

// ───── JDM (GoRules JSON Decision Model) — subset we author + evaluate locally
export interface JdmInputField {
  id: string;
  field: string;     // dotted-path into fact, e.g. "amount"
  name?: string;
  type?: "string" | "number" | "boolean";
}
export interface JdmOutputField {
  id: string;
  field: string;     // output key, e.g. "matched"
  name?: string;
  type?: "string" | "number" | "boolean";
}
export interface JdmRule {
  _id: string;
  // keyed by input field id → cell expression (e.g. "> 100", '== "blocked"', "in [\"a\",\"b\"]", "")
  // and by output field id → literal/expression
  [k: string]: string;
}
export interface JdmDecisionTableContent {
  hitPolicy: "first" | "collect";
  inputs: JdmInputField[];
  outputs: JdmOutputField[];
  rules: JdmRule[];
}
export interface JdmNode {
  id: string;
  name?: string;
  type: "inputNode" | "outputNode" | "decisionTableNode";
  position?: { x: number; y: number };
  content?: JdmDecisionTableContent;
}
export interface JdmEdge {
  id: string;
  sourceId: string;
  targetId: string;
}
export interface JdmGraph {
  nodes: JdmNode[];
  edges: JdmEdge[];
}

export interface Rule {
  id: UUID;
  name: string;
  description: string;
  scope: RuleScope;          // logical scope; with custom inputSchema this is informational
  status: RuleStatus;
  severity: RuleSeverity;
  action: RuleAction;
  threshold: number; // 0-1
  /** Legacy condition tree — kept for back-compat. New rules use `content`. */
  when: RuleConditionGroup;
  /** GoRules JDM graph — authoritative when present. */
  content?: JdmGraph;
  /** Optional custom input schema (generalized fact shape). */
  inputSchema?: JdmInputField[];
  tags: string[];
  created_at: string;
  updated_at: string;
  created_by: string;
  version: number;
  last_promoted_by?: string;
  last_promoted_at?: string;
}

export interface MatchedCondition {
  field: string;
  operator: RuleOperator;
  value: unknown;
  matched: boolean;
  weight: number;
  actual: unknown;
}

export interface RuleHit {
  id: UUID;
  rule_id: UUID;
  rule_version: number;
  rule_name: string;
  severity: RuleSeverity;
  action: RuleAction;
  scope: RuleScope;
  subject_id: UUID;
  confidence: number; // 0-1
  matched_conditions: MatchedCondition[];
  evaluated_at: string;
  mode: "live" | "sandbox";
}

// ───── Recommendations (mock — really sourced from alvera-ai/platform)
export type RecommendationKind =
  | "add_blocklist_entry"
  | "raise_risk_classification"
  | "request_kyc_document"
  | "suspend_counterparty";

export interface Recommendation {
  id: UUID;
  kind: RecommendationKind;
  subject_type: "account_holder" | "counterparty" | "transaction";
  subject_id: UUID;
  subject_label: string;
  signal: string;
  rationale: string;
  confidence: number; // 0–1
  created_at: string;
  status: "open" | "approved" | "dismissed";
  payload: Record<string, unknown>;
}
