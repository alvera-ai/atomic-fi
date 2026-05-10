import { useEffect, useMemo, useState } from "react";
import { format } from "date-fns";
import { Briefcase, RotateCcw } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { StatusPill } from "@/components/status-pill";
import { cn } from "@/lib/utils";
import {
  ASSIGNEE_OPTIONS,
  listCases,
  subscribeCases,
  type Case,
  type CasePriority,
  type CaseStatus,
  type CaseType,
} from "@/api/cases";
import { CaseDetail } from "@/components/cases/case-detail";

const STATUSES: CaseStatus[] = ["open", "in_progress", "pending_customer", "escalated", "closed"];
const TYPES: CaseType[] = ["transaction_flag", "onboarding_review", "sanctions_match", "rule_breach"];
const PRIORITIES: CasePriority[] = ["critical", "high", "medium", "low"];

const PRIORITY_TONE: Record<CasePriority, string> = {
  critical: "bg-destructive text-destructive-foreground",
  high: "bg-destructive/15 text-destructive border border-destructive/30",
  medium: "bg-warning/20 text-warning-foreground border border-warning/30",
  low: "bg-muted text-muted-foreground border border-border",
};

export default function CasesPage() {
  const [cases, setCases] = useState<Case[]>([]);
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<CaseStatus | "all">("all");
  const [typeFilter, setTypeFilter] = useState<CaseType | "all">("all");
  const [priorityFilter, setPriorityFilter] = useState<CasePriority | "all">("all");
  const [assigneeFilter, setAssigneeFilter] = useState<string | "all">("all");
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const refresh = () => listCases().then(setCases);
  useEffect(() => {
    refresh();
    const unsub = subscribeCases(refresh);
    return () => { unsub(); };
  }, []);

  const filtered = useMemo(() => {
    const s = search.trim().toLowerCase();
    return cases.filter((c) => {
      if (statusFilter !== "all" && c.status !== statusFilter) return false;
      if (typeFilter !== "all" && c.type !== typeFilter) return false;
      if (priorityFilter !== "all" && c.priority !== priorityFilter) return false;
      if (assigneeFilter !== "all" && c.assigned_to !== assigneeFilter) return false;
      if (s) {
        const blob = `${c.id} ${c.title} ${c.description} ${c.assigned_to}`.toLowerCase();
        if (!blob.includes(s)) return false;
      }
      return true;
    });
  }, [cases, search, statusFilter, typeFilter, priorityFilter, assigneeFilter]);

  const selected = cases.find((c) => c.id === selectedId) ?? null;

  const reset = () => {
    setSearch(""); setStatusFilter("all"); setTypeFilter("all");
    setPriorityFilter("all"); setAssigneeFilter("all");
  };

  return (
    <div className="flex h-full">
      <div className="flex min-w-0 flex-1 flex-col gap-3 p-4">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-semibold tracking-tight">Cases</h1>
            <p className="text-xs text-muted-foreground">
              {filtered.length} of {cases.length} cases requiring review
            </p>
          </div>
        </div>

        <Card className="p-3">
          <div className="flex flex-wrap items-center gap-2">
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search title, description, assignee…"
              className="h-9 w-[260px]"
            />
            <Select value={statusFilter} onValueChange={(v) => setStatusFilter(v as CaseStatus | "all")}>
              <SelectTrigger className="h-9 w-[170px]"><SelectValue placeholder="Status" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All statuses</SelectItem>
                {STATUSES.map((s) => <SelectItem key={s} value={s}>{s.replace(/_/g, " ")}</SelectItem>)}
              </SelectContent>
            </Select>
            <Select value={typeFilter} onValueChange={(v) => setTypeFilter(v as CaseType | "all")}>
              <SelectTrigger className="h-9 w-[180px]"><SelectValue placeholder="Type" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All types</SelectItem>
                {TYPES.map((t) => <SelectItem key={t} value={t}>{t.replace(/_/g, " ")}</SelectItem>)}
              </SelectContent>
            </Select>
            <Select value={priorityFilter} onValueChange={(v) => setPriorityFilter(v as CasePriority | "all")}>
              <SelectTrigger className="h-9 w-[150px]"><SelectValue placeholder="Priority" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All priorities</SelectItem>
                {PRIORITIES.map((p) => <SelectItem key={p} value={p}>{p}</SelectItem>)}
              </SelectContent>
            </Select>
            <Select value={assigneeFilter} onValueChange={setAssigneeFilter}>
              <SelectTrigger className="h-9 w-[180px]"><SelectValue placeholder="Assigned to" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All assignees</SelectItem>
                {ASSIGNEE_OPTIONS.map((a) => <SelectItem key={a} value={a}>{a}</SelectItem>)}
              </SelectContent>
            </Select>
            <Button variant="ghost" size="sm" onClick={reset} className="gap-1.5">
              <RotateCcw className="h-3.5 w-3.5" /> Reset
            </Button>
          </div>
        </Card>

        <Card className="min-h-0 flex-1 overflow-hidden">
          <div className="h-full overflow-auto">
            <table className="w-full text-sm">
              <thead className="sticky top-0 z-10 bg-card text-left text-xs text-muted-foreground">
                <tr className="border-b">
                  <th className="px-3 py-2 font-medium">Priority</th>
                  <th className="px-3 py-2 font-medium">Type</th>
                  <th className="px-3 py-2 font-medium">Title</th>
                  <th className="px-3 py-2 font-medium">Assigned to</th>
                  <th className="px-3 py-2 font-medium">Status</th>
                  <th className="px-3 py-2 font-medium">Due date</th>
                  <th className="px-3 py-2 font-medium">Updated</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((c) => (
                  <tr
                    key={c.id}
                    onClick={() => setSelectedId(c.id)}
                    className={cn(
                      "cursor-pointer border-b transition hover:bg-muted/40",
                      selectedId === c.id && "bg-primary/5",
                    )}
                  >
                    <td className="px-3 py-2">
                      <span className={`inline-block rounded-full px-2 py-0.5 text-[11px] font-medium capitalize ${PRIORITY_TONE[c.priority]}`}>
                        {c.priority}
                      </span>
                    </td>
                    <td className="px-3 py-2 text-xs capitalize">{c.type.replace(/_/g, " ")}</td>
                    <td className="px-3 py-2">
                      <div className="text-xs font-medium">{c.title}</div>
                      <div className="truncate text-[11px] text-muted-foreground">{c.description}</div>
                    </td>
                    <td className="px-3 py-2 text-xs">{c.assigned_to}</td>
                    <td className="px-3 py-2"><StatusPill value={c.status} /></td>
                    <td className="px-3 py-2 text-xs text-muted-foreground">{format(new Date(c.due_date), "yyyy-MM-dd")}</td>
                    <td className="px-3 py-2 text-xs text-muted-foreground">{format(new Date(c.updated_at), "yyyy-MM-dd")}</td>
                  </tr>
                ))}
                {filtered.length === 0 && (
                  <tr><td colSpan={7} className="p-8 text-center text-sm text-muted-foreground">No cases match.</td></tr>
                )}
              </tbody>
            </table>
          </div>
        </Card>
      </div>

      <aside className="hidden w-[480px] shrink-0 border-l bg-background xl:block">
        {selected ? (
          <CaseDetail value={selected} onChanged={refresh} />
        ) : (
          <div className="flex h-full flex-col items-center justify-center gap-2 p-8 text-center text-sm text-muted-foreground">
            <div className="flex h-10 w-10 items-center justify-center rounded-full bg-muted">
              <Briefcase className="h-4 w-4" />
            </div>
            Select a case to view its details.
          </div>
        )}
      </aside>
    </div>
  );
}
