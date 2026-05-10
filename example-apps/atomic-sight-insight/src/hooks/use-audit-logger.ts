import { useAuth } from "@/contexts/auth-context";
import { appendAudit, type AppendAuditInput, type AuditActionType, type AuditResourceType } from "@/api/audit";

export interface LogActionInput {
  action_type: AuditActionType;
  resource_type: AuditResourceType;
  resource_id: string;
  description: string;
  metadata?: Record<string, unknown>;
}

export function useAuditLogger() {
  const { user } = useAuth();
  return (input: LogActionInput) => {
    const entry: AppendAuditInput = {
      actor_name: user.name,
      actor_role: user.role,
      action_type: input.action_type,
      resource_type: input.resource_type,
      resource_id: input.resource_id,
      description: input.description,
      metadata: input.metadata ?? {},
    };
    return appendAudit(entry);
  };
}
