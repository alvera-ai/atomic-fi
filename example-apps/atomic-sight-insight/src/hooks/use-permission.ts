import { useAuth } from "@/contexts/auth-context";
import { hasPermission } from "@/lib/permissions";

export function usePermission(action: string): boolean {
  const { user } = useAuth();
  return hasPermission(user.role, action);
}
