import type { UserRole } from "@/contexts/auth-context";

export type AuditActionType =
  | "rule.created"
  | "rule.edited"
  | "rule.promoted"
  | "rule.archived"
  | "transaction.status_updated"
  | "case.created"
  | "case.assigned"
  | "case.closed"
  | "case.escalated"
  | "onboarding.approved"
  | "onboarding.rejected"
  | "outreach.sent"
  | "screening.dispositioned";

export type AuditResourceType = "rule" | "transaction" | "case" | "account_holder" | "screening";

export interface AuditEntry {
  id: string;
  timestamp: string;
  actor_name: string;
  actor_role: UserRole;
  action_type: AuditActionType;
  resource_type: AuditResourceType;
  resource_id: string;
  description: string;
  metadata: Record<string, unknown>;
}

export const ACTION_TYPES: AuditActionType[] = [
  "rule.created", "rule.edited", "rule.promoted", "rule.archived",
  "transaction.status_updated",
  "case.created", "case.assigned", "case.closed", "case.escalated",
  "onboarding.approved", "onboarding.rejected",
  "outreach.sent", "screening.dispositioned",
];

export const RESOURCE_TYPES: AuditResourceType[] = ["rule", "transaction", "case", "account_holder", "screening"];

export const RESOURCE_ROUTE: Record<AuditResourceType, string> = {
  rule: "/rules",
  transaction: "/transactions",
  case: "/queue",
  account_holder: "/customers",
  screening: "/queue?tab=sanctions",
};

const daysAgo = (n: number, h = 0) =>
  new Date(Date.now() - n * 86_400_000 - h * 3_600_000).toISOString();

const seed: AuditEntry[] = [
  { id: "al_001", timestamp: daysAgo(0, 1), actor_name: "Alex Ortega", actor_role: "compliance_officer", action_type: "rule.promoted", resource_type: "rule", resource_id: "rule_005", description: "Promoted rule 'Sanctioned creditor jurisdiction' from Sandbox to Live", metadata: { from: "sandbox", to: "live" } },
  { id: "al_002", timestamp: daysAgo(0, 3), actor_name: "Priya Shah", actor_role: "compliance_analyst", action_type: "case.assigned", resource_type: "case", resource_id: "case_0002", description: "Assigned case 'Potential sanctions match' to Marcus Chen", metadata: { assignee: "Marcus Chen" } },
  { id: "al_003", timestamp: daysAgo(0, 5), actor_name: "Marcus Chen", actor_role: "compliance_ops_agent", action_type: "outreach.sent", resource_type: "account_holder", resource_id: "ah_103", description: "Sent outreach 'Source of funds verification' to ops@nordicfreight.se", metadata: { template: "source_of_funds" } },
  { id: "al_004", timestamp: daysAgo(1, 2), actor_name: "Ana Martins", actor_role: "compliance_officer", action_type: "case.closed", resource_type: "case", resource_id: "case_0007", description: "Closed case 'Duplicate payment instruction — resolved'", metadata: {} },
  { id: "al_005", timestamp: daysAgo(1, 6), actor_name: "James Osei", actor_role: "rules_manager", action_type: "rule.edited", resource_type: "rule", resource_id: "rule_007", description: "Edited rule 'Velocity: large transfers in 24h' (threshold 100k → 75k)", metadata: { field: "threshold" } },
  { id: "al_006", timestamp: daysAgo(2, 1), actor_name: "Sofía Reyes", actor_role: "compliance_analyst", action_type: "screening.dispositioned", resource_type: "screening", resource_id: "scr_021", description: "Marked screening match as false positive (common name)", metadata: { qualifier: "common_name" } },
  { id: "al_007", timestamp: daysAgo(2, 4), actor_name: "Liam O'Connor", actor_role: "compliance_ops_agent", action_type: "transaction.status_updated", resource_type: "transaction", resource_id: "tx_900145", description: "Updated transaction status from pending to rejected", metadata: { from: "pending", to: "rejected" } },
  { id: "al_008", timestamp: daysAgo(3, 0), actor_name: "Yuki Tanaka", actor_role: "compliance_analyst", action_type: "onboarding.approved", resource_type: "account_holder", resource_id: "ah_106", description: "Approved KYC for Helios Energy GmbH", metadata: {} },
  { id: "al_009", timestamp: daysAgo(3, 8), actor_name: "Alex Ortega", actor_role: "compliance_officer", action_type: "case.escalated", resource_type: "case", resource_id: "case_0005", description: "Escalated case 'Holder over 1M USD with high-risk country' to MLRO", metadata: { priority: "critical" } },
  { id: "al_010", timestamp: daysAgo(4, 3), actor_name: "Priya Shah", actor_role: "compliance_analyst", action_type: "case.created", resource_type: "case", resource_id: "case_0008", description: "Created case 'PEP exposure detected on new beneficial owner'", metadata: { type: "sanctions_match" } },
  { id: "al_011", timestamp: daysAgo(5, 5), actor_name: "James Osei", actor_role: "rules_manager", action_type: "rule.created", resource_type: "rule", resource_id: "rule_010", description: "Created rule 'High-velocity card payments'", metadata: { status: "sandbox" } },
  { id: "al_012", timestamp: daysAgo(6, 2), actor_name: "Marcus Chen", actor_role: "compliance_ops_agent", action_type: "outreach.sent", resource_type: "transaction", resource_id: "tx_900042", description: "Sent outreach 'Additional documentation required' to ops@acme.io", metadata: { template: "additional_documentation" } },
  { id: "al_013", timestamp: daysAgo(8, 1), actor_name: "Ana Martins", actor_role: "compliance_officer", action_type: "rule.archived", resource_type: "rule", resource_id: "rule_009", description: "Archived rule 'Legacy: any transfer over 100k'", metadata: {} },
  { id: "al_014", timestamp: daysAgo(9, 4), actor_name: "Sofía Reyes", actor_role: "compliance_analyst", action_type: "onboarding.rejected", resource_type: "account_holder", resource_id: "ah_107", description: "Rejected KYC for Maria González (sanctions match)", metadata: {} },
  { id: "al_015", timestamp: daysAgo(11, 6), actor_name: "Liam O'Connor", actor_role: "compliance_ops_agent", action_type: "transaction.status_updated", resource_type: "transaction", resource_id: "tx_900218", description: "Updated transaction status from pending to accepted", metadata: { from: "pending", to: "accepted" } },
  { id: "al_016", timestamp: daysAgo(13, 2), actor_name: "Yuki Tanaka", actor_role: "compliance_analyst", action_type: "case.assigned", resource_type: "case", resource_id: "case_0006", description: "Assigned case 'Beneficial owner verification pending' to Liam O'Connor", metadata: {} },
  { id: "al_017", timestamp: daysAgo(15, 3), actor_name: "Alex Ortega", actor_role: "compliance_officer", action_type: "rule.promoted", resource_type: "rule", resource_id: "rule_002", description: "Promoted rule 'High-risk holder over 1M USD' from Sandbox to Live", metadata: { from: "sandbox", to: "live" } },
  { id: "al_018", timestamp: daysAgo(18, 5), actor_name: "Priya Shah", actor_role: "compliance_analyst", action_type: "screening.dispositioned", resource_type: "screening", resource_id: "scr_018", description: "Cleared screening after manual verification of identity", metadata: {} },
  { id: "al_019", timestamp: daysAgo(22, 1), actor_name: "Marcus Chen", actor_role: "compliance_ops_agent", action_type: "case.created", resource_type: "case", resource_id: "case_0004", description: "Created case 'Manually flagged: unusual cross-border pattern'", metadata: { priority: "high" } },
  { id: "al_020", timestamp: daysAgo(28, 4), actor_name: "James Osei", actor_role: "rules_manager", action_type: "rule.edited", resource_type: "rule", resource_id: "rule_003", description: "Edited rule 'Sanctioned creditor jurisdiction' added new sanctioned countries", metadata: {} },
];

let store: AuditEntry[] = [...seed];
const subscribers = new Set<() => void>();
const notify = () => subscribers.forEach((fn) => fn());

const delay = <T,>(v: T, ms = 100) => new Promise<T>((r) => setTimeout(() => r(v), ms));

export const listAuditEntries = () =>
  delay([...store].sort((a, b) => b.timestamp.localeCompare(a.timestamp)));

export type AppendAuditInput = Omit<AuditEntry, "id" | "timestamp">;

export const appendAudit = (entry: AppendAuditInput): AuditEntry => {
  const created: AuditEntry = {
    ...entry,
    id: `al_${Math.random().toString(16).slice(2, 8)}`,
    timestamp: new Date().toISOString(),
    metadata: entry.metadata ?? {},
  };
  store = [created, ...store];
  notify();
  return created;
};

export const subscribeAudit = (fn: () => void) => {
  subscribers.add(fn);
  return () => subscribers.delete(fn);
};
