import type { UserRole } from "@/contexts/auth-context";

export const NAV_ACCESS: Record<string, UserRole[]> = {
  "/dashboard": ["compliance_officer", "auditor"],
  "/queue": ["compliance_officer", "compliance_analyst", "compliance_ops_agent", "auditor"],
  "/customers": ["compliance_officer", "compliance_analyst", "compliance_ops_agent", "auditor"],
  "/transactions": ["compliance_officer", "compliance_analyst", "compliance_ops_agent", "rules_manager", "auditor"],
  "/rules": ["compliance_officer", "compliance_analyst", "rules_manager", "auditor"],
  "/integrations": ["engineer"],
  "/health": ["engineer"],
};

export const ROLE_DEFAULT_ROUTE: Record<UserRole, string> = {
  compliance_officer: "/dashboard",
  compliance_analyst: "/queue",
  compliance_ops_agent: "/queue",
  rules_manager: "/rules",
  engineer: "/health",
  auditor: "/dashboard",
};

export function canAccessRoute(role: UserRole, path: string): boolean {
  const match = Object.keys(NAV_ACCESS).find(
    (p) => path === p || path.startsWith(p + "/"),
  );
  if (!match) return true;
  return NAV_ACCESS[match].includes(role);
}
