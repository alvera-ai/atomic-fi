import { ShieldCheck } from "lucide-react";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { ALL_ROLES, useAuth, type UserRole } from "@/contexts/auth-context";

export function RoleSwitcher() {
  const { user, setRole } = useAuth();
  return (
    <Select value={user.role} onValueChange={(v) => setRole(v as UserRole)}>
      <SelectTrigger className="h-9 w-[200px] gap-2" aria-label="Switch role">
        <ShieldCheck className="h-4 w-4 text-muted-foreground" />
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {ALL_ROLES.map((r) => (
          <SelectItem key={r.value} value={r.value}>
            {r.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
