import type { ReactNode } from "react";
import { usePermission } from "@/hooks/use-permission";

interface RoleGateProps {
  action: string;
  children: ReactNode;
  fallback?: ReactNode;
}

export function RoleGate({ action, children, fallback = null }: RoleGateProps) {
  const allowed = usePermission(action);
  if (!allowed) return <>{fallback}</>;
  return <>{children}</>;
}
