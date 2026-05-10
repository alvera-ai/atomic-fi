import type { UserRole } from "@/contexts/auth-context";

export const PERMISSIONS: Record<string, UserRole[]> = {
  "transaction.update_status": ["compliance_officer", "compliance_analyst"],
  "transaction.create_flag": ["compliance_officer", "compliance_analyst"],
  "transaction.outreach": ["compliance_officer", "compliance_analyst", "compliance_ops_agent"],
  "onboarding.approve": ["compliance_officer", "compliance_analyst"],
  "onboarding.request_docs": ["compliance_officer", "compliance_analyst", "compliance_ops_agent"],
  "review.disposition": ["compliance_officer", "compliance_analyst"],
  "rule.view": ["compliance_officer", "compliance_analyst", "rules_manager", "auditor"],
  "rule.create": ["compliance_officer", "rules_manager"],
  "rule.promote": ["compliance_officer"],
  "rule.archive": ["compliance_officer"],
  "rule.backtest": ["compliance_officer", "rules_manager"],
  "talk_to_data.access": ["compliance_officer", "compliance_analyst", "rules_manager", "auditor"],
  "recommendations.approve": ["compliance_officer"],
  "integrations.access": ["engineer"],
  "health.access": ["engineer"],
  "audit.view": ["compliance_officer", "auditor"],
  "audit.export": ["compliance_officer", "auditor"],
};

export function hasPermission(role: UserRole, action: string): boolean {
  const allowed = PERMISSIONS[action];
  if (!allowed) return false;
  return allowed.includes(role);
}
