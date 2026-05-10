import { useMemo, useState } from "react";
import { format } from "date-fns";
import { ArrowUpRight, MessageSquare, ShieldAlert, X, ChevronUp } from "lucide-react";
import { Link } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { toast } from "sonner";
import { StatusPill } from "@/components/status-pill";
import { useAuth } from "@/contexts/auth-context";
import { useAuditLogger } from "@/hooks/use-audit-logger";
import {
  ASSIGNEE_OPTIONS,
  addCaseNote,
  updateCase,
  type Case,
  type CaseStatus,
} from "@/api/cases";
import { accountHolders, transactions } from "@/data/fixtures";

const PRIORITY_TONE: Record<string, string> = {
  critical: "bg-destructive text-destructive-foreground",
  high: "bg-destructive/15 text-destructive border border-destructive/30",
  medium: "bg-warning/20 text-warning-foreground border border-warning/30",
  low: "bg-muted text-muted-foreground border border-border",
};

const ALL_STATUSES: CaseStatus[] = ["open", "in_progress", "pending_customer", "escalated", "closed"];

export function CaseDetail({ value, onChanged, extraActions }: { value: Case; onChanged: () => void; extraActions?: React.ReactNode }) {
  const { user } = useAuth();
  const role = user.role;
  const [note, setNote] = useState("");
  const [confirmClose, setConfirmClose] = useState(false);
  const [confirmEsc, setConfirmEsc] = useState(false);

  const isAuditor = role === "auditor";
  const isOpsAgent = role === "compliance_ops_agent";
  const isAnalyst = role === "compliance_analyst";
  const isOfficer = role === "compliance_officer";

  const canAddNote = !isAuditor;
  const canReassign = isOfficer || isAnalyst;
  const canCloseOrEscalate = isOfficer;

  const allowedStatuses = useMemo<CaseStatus[]>(() => {
    if (isOfficer || isAnalyst) return ALL_STATUSES;
    if (isOpsAgent) return Array.from(new Set([value.status, "pending_customer"])) as CaseStatus[];
    return [value.status];
  }, [isOfficer, isAnalyst, isOpsAgent, value.status]);

  const canChangeStatus = allowedStatuses.length > 1;

  const sourceHref =
    value.source_type === "transaction" ? `/transactions?focus=${value.source_id}` : `/customers?focus=${value.source_id}`;
  const sourceLabel =
    value.source_type === "transaction"
      ? transactions.find((t) => t.id === value.source_id)?.id.slice(0, 10) ?? value.source_id.slice(0, 10)
      : accountHolders.find((h) => h.id === value.source_id)?.display_name ?? value.source_id.slice(0, 10);

  const logAudit = useAuditLogger();

  const doStatus = async (s: CaseStatus) => {
    await updateCase(value.id, { status: s });
    toast.success("Status updated", { description: s.replace(/_/g, " ") });
    onChanged();
  };

  const doAssign = async (assignee: string) => {
    await updateCase(value.id, { assigned_to: assignee });
    logAudit({
      action_type: "case.assigned",
      resource_type: "case",
      resource_id: value.id,
      description: `Assigned case '${value.title}' to ${assignee}`,
      metadata: { assignee },
    });
    toast.success("Reassigned", { description: assignee });
    onChanged();
  };

  const doNote = async () => {
    if (!note.trim()) return;
    await addCaseNote(value.id, { author: user.name, text: note.trim(), timestamp: new Date().toISOString() });
    setNote("");
    onChanged();
  };

  const doClose = async () => {
    await updateCase(value.id, { status: "closed" });
    logAudit({
      action_type: "case.closed",
      resource_type: "case",
      resource_id: value.id,
      description: `Closed case '${value.title}'`,
      metadata: {},
    });
    toast.success("Case closed");
    setConfirmClose(false);
    onChanged();
  };

  const doEscalate = async () => {
    await updateCase(value.id, { status: "escalated", priority: "critical" });
    logAudit({
      action_type: "case.escalated",
      resource_type: "case",
      resource_id: value.id,
      description: `Escalated case '${value.title}' to critical priority`,
      metadata: { priority: "critical" },
    });
    toast.success("Case escalated");
    setConfirmEsc(false);
    onChanged();
  };

  return (
    <div className="flex h-full flex-col">
      <div className="space-y-2 border-b p-4">
        <div className="text-[11px] font-mono text-muted-foreground">{value.id}</div>
        <div className="flex flex-wrap items-center gap-2">
          <span className={`rounded-full px-2 py-0.5 text-[11px] font-medium capitalize ${PRIORITY_TONE[value.priority]}`}>
            {value.priority}
          </span>
          <span className="text-xs capitalize text-muted-foreground">{value.type.replace(/_/g, " ")}</span>
          <span className="ml-auto"><StatusPill value={value.status} /></span>
        </div>
        <div className="text-base font-semibold">{value.title}</div>
        <p className="text-xs text-muted-foreground">{value.description}</p>

        {isAuditor && (
          <div className="rounded-md border border-dashed bg-muted/40 px-2.5 py-1.5 text-[11px] text-muted-foreground">
            You have read-only access to this record.
          </div>
        )}
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto p-4 space-y-4">
        <div className="rounded-md border bg-card p-3 space-y-3">
          <div className="grid grid-cols-[110px_1fr] gap-y-2 text-xs">
            <div className="text-muted-foreground">Source</div>
            <Link to={sourceHref} className="inline-flex items-center gap-1 font-medium text-primary hover:underline">
              {value.source_type === "transaction" ? "Transaction" : "Account holder"} · {sourceLabel}
              <ArrowUpRight className="h-3 w-3" />
            </Link>

            <div className="text-muted-foreground">Status</div>
            <div>
              {canChangeStatus ? (
                <Select value={value.status} onValueChange={(v) => doStatus(v as CaseStatus)}>
                  <SelectTrigger className="h-8 w-[200px]"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {allowedStatuses.map((s) => (
                      <SelectItem key={s} value={s}>{s.replace(/_/g, " ")}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              ) : (
                <StatusPill value={value.status} />
              )}
            </div>

            <div className="text-muted-foreground">Assigned to</div>
            <div>
              {canReassign ? (
                <Select value={value.assigned_to} onValueChange={doAssign}>
                  <SelectTrigger className="h-8 w-[200px]"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {ASSIGNEE_OPTIONS.map((a) => (
                      <SelectItem key={a} value={a}>{a}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              ) : (
                <span className="font-medium">{value.assigned_to}</span>
              )}
            </div>

            <div className="text-muted-foreground">Due date</div>
            <div className="font-medium">{format(new Date(value.due_date), "yyyy-MM-dd")}</div>

            <div className="text-muted-foreground">Created</div>
            <div className="text-muted-foreground">{format(new Date(value.created_at), "yyyy-MM-dd HH:mm")}</div>

            <div className="text-muted-foreground">Updated</div>
            <div className="text-muted-foreground">{format(new Date(value.updated_at), "yyyy-MM-dd HH:mm")}</div>
          </div>

          {canCloseOrEscalate && (
            <div className="flex flex-wrap gap-1.5 border-t pt-3">
              <Button size="sm" variant="outline" onClick={() => setConfirmEsc(true)} disabled={value.status === "escalated"} className="gap-1.5">
                <ChevronUp className="h-3.5 w-3.5" /> Escalate
              </Button>
              <Button size="sm" variant="outline" onClick={() => setConfirmClose(true)} disabled={value.status === "closed"} className="gap-1.5">
                <X className="h-3.5 w-3.5" /> Close case
              </Button>
            </div>
          )}
          {extraActions && <div className="border-t pt-3">{extraActions}</div>}
        </div>

        <div className="rounded-md border bg-card">
          <div className="flex items-center gap-2 border-b px-3 py-2 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
            <MessageSquare className="h-3.5 w-3.5" /> Activity ({value.notes.length})
          </div>
          <ul className="divide-y">
            {value.notes.length === 0 && (
              <li className="px-3 py-4 text-xs text-muted-foreground">No notes yet.</li>
            )}
            {value.notes.map((n, i) => (
              <li key={i} className="px-3 py-2 text-xs">
                <div className="flex items-center gap-2">
                  <span className="font-medium">{n.author}</span>
                  <span className="ml-auto text-muted-foreground">{format(new Date(n.timestamp), "yyyy-MM-dd HH:mm")}</span>
                </div>
                <p className="mt-0.5 text-muted-foreground">{n.text}</p>
              </li>
            ))}
          </ul>
          {canAddNote && (
            <div className="border-t p-3 space-y-2">
              <Textarea
                placeholder="Add an internal note…"
                value={note}
                onChange={(e) => setNote(e.target.value)}
                rows={2}
              />
              <div className="flex justify-end">
                <Button size="sm" onClick={doNote} disabled={!note.trim()}>Add note</Button>
              </div>
            </div>
          )}
        </div>
      </div>

      <AlertDialog open={confirmClose} onOpenChange={setConfirmClose}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Close this case?</AlertDialogTitle>
            <AlertDialogDescription>
              The case will be marked as closed. You can reopen it by changing the status.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={doClose}>Close case</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <AlertDialog open={confirmEsc} onOpenChange={setConfirmEsc}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Escalate this case?</AlertDialogTitle>
            <AlertDialogDescription>
              Priority will be raised to critical and the case will be marked as escalated.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={doEscalate}>
              <ShieldAlert className="mr-1.5 h-3.5 w-3.5" /> Escalate
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
