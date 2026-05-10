import { createContext, useContext, useMemo, useState, type ReactNode } from "react";

export type UserRole =
  | "compliance_officer"
  | "compliance_analyst"
  | "compliance_ops_agent"
  | "rules_manager"
  | "engineer"
  | "auditor";

export interface AuthUser {
  id: string;
  name: string;
  email: string;
  role: UserRole;
}

interface AuthContextValue {
  user: AuthUser;
  setRole: (role: UserRole) => void;
}

const DEFAULT_USER: AuthUser = {
  id: "u_001",
  name: "Alex Ortega",
  email: "alex@alvera.ai",
  role: "compliance_officer",
};

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser>(DEFAULT_USER);
  const value = useMemo<AuthContextValue>(
    () => ({
      user,
      setRole: (role) => setUser((u) => ({ ...u, role })),
    }),
    [user],
  );
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used within AuthProvider");
  return ctx;
}

export const ALL_ROLES: { value: UserRole; label: string }[] = [
  { value: "compliance_officer", label: "Compliance Officer" },
  { value: "compliance_analyst", label: "Compliance Analyst" },
  { value: "compliance_ops_agent", label: "Compliance Ops Agent" },
  { value: "rules_manager", label: "Rules Manager" },
  { value: "engineer", label: "Engineer" },
  { value: "auditor", label: "Auditor" },
];
