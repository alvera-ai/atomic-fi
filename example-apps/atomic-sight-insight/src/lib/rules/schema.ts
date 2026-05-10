import type { RuleOperator, RuleScope } from "@/api/types";

export type FieldType = "number" | "string" | "enum" | "boolean";

export interface FieldDef {
  path: string;
  label: string;
  type: FieldType;
  values?: string[];
}

export const TX_FIELDS: FieldDef[] = [
  { path: "amount", label: "Amount (minor units)", type: "number" },
  { path: "currency", label: "Currency", type: "enum", values: ["USD", "EUR", "GBP", "JPY"] },
  { path: "status", label: "Status", type: "enum", values: ["pending", "accepted", "settled", "rejected", "reversed", "cancelled"] },
  { path: "transaction_type", label: "Type", type: "enum", values: ["credit_transfer", "direct_debit", "card_payment", "refund", "reversal", "internal_transfer"] },
  { path: "creditor_counterparty.status", label: "Creditor status", type: "enum", values: ["active", "blocked", "under_review", "suspended"] },
  { path: "creditor_counterparty.country", label: "Creditor country", type: "string" },
  { path: "debtor_counterparty.status", label: "Debtor status", type: "enum", values: ["active", "blocked", "under_review", "suspended"] },
  { path: "account_holder.risk_level", label: "Holder risk", type: "enum", values: ["low", "medium", "high", "prohibited"] },
  { path: "account_holder.kyc_status", label: "Holder KYC", type: "enum", values: ["not_started", "in_progress", "approved", "rejected", "on_hold"] },
  { path: "account_holder.country", label: "Holder country", type: "string" },
  { path: "latest_screening.status", label: "Latest screening", type: "enum", values: ["clear", "potential_match", "match", "review"] },
  { path: "has_pep_owner", label: "Has PEP beneficial owner", type: "boolean" },
];

export const HOLDER_FIELDS: FieldDef[] = [
  { path: "risk_level", label: "Risk level", type: "enum", values: ["low", "medium", "high", "prohibited"] },
  { path: "kyc_status", label: "KYC status", type: "enum", values: ["not_started", "in_progress", "approved", "rejected", "on_hold"] },
  { path: "country", label: "Country", type: "string" },
  { path: "entity_type", label: "Entity type", type: "enum", values: ["individual", "business"] },
  { path: "open_kyc_requirements_count", label: "Open KYC reqs", type: "number" },
  { path: "rejected_kyc_requirements_count", label: "Rejected KYC reqs", type: "number" },
  { path: "documents_count", label: "Documents on file", type: "number" },
  { path: "latest_screening.status", label: "Latest screening", type: "enum", values: ["clear", "potential_match", "match", "review"] },
];

export const fieldsForScope = (scope: RuleScope): FieldDef[] =>
  scope === "transaction" ? TX_FIELDS : HOLDER_FIELDS;

export const fieldDef = (scope: RuleScope, path: string): FieldDef | undefined =>
  fieldsForScope(scope).find((f) => f.path === path);

export const OPERATORS: { value: RuleOperator; label: string; types: FieldType[] }[] = [
  { value: "eq", label: "equals", types: ["number", "string", "enum", "boolean"] },
  { value: "neq", label: "not equals", types: ["number", "string", "enum", "boolean"] },
  { value: "in", label: "in", types: ["string", "enum"] },
  { value: "not_in", label: "not in", types: ["string", "enum"] },
  { value: "gt", label: ">", types: ["number"] },
  { value: "gte", label: "≥", types: ["number"] },
  { value: "lt", label: "<", types: ["number"] },
  { value: "lte", label: "≤", types: ["number"] },
  { value: "between", label: "between", types: ["number"] },
  { value: "contains", label: "contains", types: ["string"] },
  { value: "exists", label: "exists", types: ["number", "string", "enum", "boolean"] },
];

export const operatorsForType = (t: FieldType) => OPERATORS.filter((o) => o.types.includes(t));
