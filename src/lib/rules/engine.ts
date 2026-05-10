import type {
  AccountHolderResponse,
  BeneficialOwnerResponse,
  ComplianceScreeningResponse,
  CounterpartyResponse,
  DocumentResponse,
  KycRequirementResponse,
  MatchedCondition,
  Rule,
  RuleCondition,
  RuleConditionGroup,
  RuleHit,
  RuleNode,
  RuleOperator,
  TransactionResponse,
} from "@/api/types";

// ─── Fact builders flatten linked entities into a dotted-path object.
export interface FactSources {
  accountHolders: AccountHolderResponse[];
  counterparties: CounterpartyResponse[];
  beneficialOwners: BeneficialOwnerResponse[];
  kycRequirements: KycRequirementResponse[];
  documents: DocumentResponse[];
  screenings: ComplianceScreeningResponse[];
}

export function buildTransactionFact(tx: TransactionResponse, src: FactSources): Record<string, unknown> {
  const holder = src.accountHolders.find((h) => h.id === tx.account_holder_id);
  const creditor = tx.creditor_counterparty_id ? src.counterparties.find((c) => c.id === tx.creditor_counterparty_id) : undefined;
  const debtor = tx.debtor_counterparty_id ? src.counterparties.find((c) => c.id === tx.debtor_counterparty_id) : undefined;
  const cpId = creditor?.id ?? debtor?.id;
  const ubos = cpId ? src.beneficialOwners.filter((b) => b.counterparty_id === cpId) : [];
  const screening = tx.compliance_screening_id ? src.screenings.find((s) => s.id === tx.compliance_screening_id) : undefined;
  return {
    amount: tx.amount,
    currency: tx.currency,
    status: tx.status,
    transaction_type: tx.transaction_type,
    "creditor_counterparty.status": creditor?.status,
    "creditor_counterparty.country": creditor?.country,
    "debtor_counterparty.status": debtor?.status,
    "account_holder.risk_level": holder?.risk_level,
    "account_holder.kyc_status": holder?.kyc_status,
    "account_holder.country": holder?.country,
    "latest_screening.status": screening?.status,
    has_pep_owner: ubos.some((u) => u.is_pep),
  };
}

export function buildHolderFact(holder: AccountHolderResponse, src: FactSources): Record<string, unknown> {
  const reqs = src.kycRequirements.filter((k) => k.account_holder_id === holder.id);
  const docs = src.documents.filter((d) => d.account_holder_id === holder.id);
  const screening = src.screenings
    .filter((s) => s.subject_type === "account_holder" && s.subject_id === holder.id)
    .sort((a, b) => b.screened_at.localeCompare(a.screened_at))[0];
  return {
    risk_level: holder.risk_level,
    kyc_status: holder.kyc_status,
    country: holder.country,
    entity_type: holder.entity_type,
    open_kyc_requirements_count: reqs.filter((r) => r.status === "pending" || r.status === "submitted").length,
    rejected_kyc_requirements_count: reqs.filter((r) => r.status === "rejected").length,
    documents_count: docs.length,
    "latest_screening.status": screening?.status,
  };
}

// ─── Operator evaluation
function evalCondition(actual: unknown, op: RuleOperator, value: unknown): boolean {
  switch (op) {
    case "exists": return actual !== null && actual !== undefined;
    case "eq": return actual === value;
    case "neq": return actual !== value;
    case "in": return Array.isArray(value) && (value as unknown[]).includes(actual);
    case "not_in": return Array.isArray(value) && !(value as unknown[]).includes(actual);
    case "gt": return typeof actual === "number" && typeof value === "number" && actual > value;
    case "gte": return typeof actual === "number" && typeof value === "number" && actual >= value;
    case "lt": return typeof actual === "number" && typeof value === "number" && actual < value;
    case "lte": return typeof actual === "number" && typeof value === "number" && actual <= value;
    case "between":
      if (!Array.isArray(value) || value.length !== 2 || typeof actual !== "number") return false;
      return actual >= (value[0] as number) && actual <= (value[1] as number);
    case "contains":
      return typeof actual === "string" && typeof value === "string" && actual.toLowerCase().includes(value.toLowerCase());
    default: return false;
  }
}

function collectLeaves(node: RuleNode): RuleCondition[] {
  if (node.kind === "condition") return [node];
  return node.children.flatMap(collectLeaves);
}

function evalGroup(node: RuleNode, fact: Record<string, unknown>): boolean {
  if (node.kind === "condition") return evalCondition(fact[node.field], node.operator, node.value);
  if (node.children.length === 0) return false;
  return node.combinator === "AND"
    ? node.children.every((c) => evalGroup(c, fact))
    : node.children.some((c) => evalGroup(c, fact));
}

import { evaluateRuleJdm } from "@/lib/rules/jdm";

export function evaluateRule(
  rule: Rule,
  fact: Record<string, unknown>,
  subjectId: string,
  mode: "live" | "sandbox" = "live",
): RuleHit | null {
  // Prefer JDM graph when present
  if (rule.content) return evaluateRuleJdm(rule, fact, subjectId, mode);

  // Legacy condition-tree path
  const fired = evalGroup(rule.when, fact);
  const leaves = collectLeaves(rule.when);
  const matched: MatchedCondition[] = leaves.map((c) => ({
    field: c.field,
    operator: c.operator,
    value: c.value,
    weight: c.weight,
    actual: fact[c.field],
    matched: evalCondition(fact[c.field], c.operator, c.value),
  }));
  const totalWeight = leaves.reduce((s, c) => s + c.weight, 0) || 1;
  const matchedWeight = matched.filter((m) => m.matched).reduce((s, m) => s + m.weight, 0);
  const confidence = matchedWeight / totalWeight;
  if (!fired || confidence < rule.threshold) return null;
  return {
    id: crypto.randomUUID(),
    rule_id: rule.id,
    rule_version: rule.version,
    rule_name: rule.name,
    severity: rule.severity,
    action: rule.action,
    scope: rule.scope,
    subject_id: subjectId,
    confidence,
    matched_conditions: matched,
    evaluated_at: new Date().toISOString(),
    mode,
  };
}

export function evaluateRules(
  rules: Rule[],
  fact: Record<string, unknown>,
  subjectId: string,
  mode: "live" | "sandbox" = "live",
): RuleHit[] {
  return rules.map((r) => evaluateRule(r, fact, subjectId, mode)).filter((h): h is RuleHit => h !== null);
}

export const newGroup = (combinator: "AND" | "OR" = "AND"): RuleConditionGroup => ({
  id: crypto.randomUUID(), kind: "group", combinator, children: [],
});
export const newCondition = (field = "amount"): RuleCondition => ({
  id: crypto.randomUUID(), kind: "condition", field, operator: "gt", value: 0, weight: 5,
});
