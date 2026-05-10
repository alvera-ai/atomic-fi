import { useEffect, useMemo, useState } from "react";
import { format } from "date-fns";
import { useSearchParams } from "react-router-dom";
import { Inbox, RefreshCcw, RotateCcw, ShieldCheck, ShieldOff, X } from "lucide-react";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { StatusPill } from "@/components/status-pill";
import { cn } from "@/lib/utils";
import {
  ASSIGNEE_OPTIONS,
  listCases,
  subscribeCases,
  type Case,
  type CasePriority,
  type CaseStatus,
} from "@/api/cases";
import { CaseDetail } from "@/components/cases/case-detail";
import { useAuth } from "@/contexts/auth-context";
import { accountHolders, transactions } from "@/data/fixtures";
import { toast } from "sonner";

type QueueTab = "all" | "transactions" | "onboarding" | "sanctions" | "escalated";

const STATUSES: CaseStatus[] = ["open", "in_progress", "pending_customer", "escalated", "closed"];
const PRIORITIES: CasePriority[] = ["critical", "high", "medium", "low"];

const PRIORITY_TONE: Record<CasePriority, string> = {
  critical: "bg-destructive text-destructive-foreground",
  high: "bg-destructive/15 text-destructive border border-destructive/30",
  medium: "bg-warning/20 text-warning-foreground border border-warning/30",
  low: "bg-muted text-muted-foreground border border-border",
};

function subjectName(c: Case): string {
  if (c.source_type === "transaction") {
    const tx = transactions.find((t) => t.id === c.source_id);
    if (!tx) return "—";
    return accountHolders.find((h) => h.id === tx.account_holder_id)?.display_name ?? "—";
  }
  return accountHolders.find((h) => h.id === c.source_id)?.display_name ?? "—";
}

function matchesTab(c: Case, tab: QueueTab): boolean {
  switch (tab) {
    case "all": return true;
    case "transactions": return c.type === "transaction_flag" || (c.type === "rule_breach" && c.source_type === "transaction");
    case "onboarding": return c.type === "onboarding_review";
    case "sanctions": return c.type === "sanctions_match";
    case "escalated": return c.status === "escalated";
  }
}

const ROLE_DEFAULT_TAB: Record<string, QueueTab> = {
  compliance_officer: "all",
  compliance_analyst: "all",
  compliance_ops_agent: "onboarding",
  rules_manager: "transactions",
  auditor: "all",
};

export default function WorkQueuePage() {
  const { user } = useAuth();
  const [params, setParams] = useSearchParams();
  const [cases, setCases] = useState<Case[]>([]);
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<CaseStatus | "all">("all");
  const [priorityFilter, setPriorityFilter] = useState<CasePriority | "all">("all");
  const [assigneeFilter, setAssigneeFilter] = useState<string>("all");
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const tab = (params.get("tab") as QueueTab) || ROLE_DEFAULT_TAB[user.role] || "all";
  const setTab = (t: QueueTab) => {
    const next = new URLSearchParams(params);
    next.set("tab", t);
    setParams(next, { replace: true });
  };

  // Auto-filter to the current user when assignee defaults are role-based
  const [meFilterActive, setMeFilterActive] = useState(
    user.role === "compliance_analyst" || user.role === "compliance_ops_agent",
  );

  useEffect(() => {
    if (!params.get("tab")) {
      const next = new URLSearchParams(params);
      next.set("tab", ROLE_DEFAULT_TAB[user.role] || "all");
      setParams(next, { replace: true });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user.role]);

  const refresh = () => listCases().then(setCases);
  useEffect(() => {
    refresh();
    const unsub = subscribeCases(refresh);
    return () => { unsub(); };
  }, []);

  const openCases = cases.filter((c) => c.status !== "closed");

  const tabCounts = useMemo(() => ({
    all: openCases.length,
    transactions: openCases.filter((c) => matchesTab(c, "transactions")).length,
    onboarding: openCases.filter((c) => matchesTab(c, "onboarding")).length,
    sanctions: openCases.filter((c) => matchesTab(c, "sanctions")).length,
    escalated: openCases.filter((c) => matchesTab(c, "escalated")).length,
  }), [openCases]);

  const filtered = useMemo(() => {
    const s = search.trim().toLowerCase();
    return cases.filter((c) => {
      if (!matchesTab(c, tab)) return false;
      if (statusFilter !== "all" && c.status !== statusFilter) return false;
      if (priorityFilter !== "all" && c.priority !== priorityFilter) return false;
      if (assigneeFilter !== "all" && c.assigned_to !== assigneeFilter) return false;
      if (meFilterActive && c.assigned_to !== user.name) return false;
      if (s) {
        const blob = `${c.id} ${c.title} ${c.description} ${c.assigned_to} ${subjectName(c)}`.toLowerCase();
        if (!blob.includes(s)) return false;
      }
      return true;
    });
  }, [cases, tab, search, statusFilter, priorityFilter, assigneeFilter, meFilterActive, user.name]);

  const visibleOpen = filtered.filter((c) => c.status === "open" || c.status === "in_progress" || c.status === "escalated").length;
  const selected = cases.find((c) => c.id === selectedId) ?? null;

  const reset = () => {
    setSearch(""); setStatusFilter("all");
    setPriorityFilter("all"); setAssigneeFilter("all");
  };

  // Sanctions extra actions
  const sanctionsActions = selected?.type === "sanctions_match" ? (
    <div className="space-y-2">
      <div className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">Sanctions actions</div>
      <div className="flex flex-wrap gap-1.5">
        <Button size="sm" variant="outline" className="gap-1.5" onClick={() => toast.success("Re-screened", { description: "POST /api/compliance-screenings/screen" })}>
          <RefreshCcw className="h-3.5 w-3.5" /> Re-screen
        </Button>
        <Button size="sm" variant="outline" className="gap-1.5" onClick={() => toast.success("Counterparty suspended")}>
          <ShieldOff className="h-3.5 w-3.5" /> Suspend counterparty
        </Button>
        <Button size="sm" variant="outline" className="gap-1.5" onClick={() => toast.success("Counterparty unblocked")}>
          <ShieldCheck className="h-3.5 w-3.5" /> Unblock
        </Button>
      </div>
    </div>
  ) : null;

  return (
    <div className="flex h-full">
      <div className="flex min-w-0 flex-1 flex-col gap-3 p-4">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-semibold tracking-tight">Work queue</h1>
            <p className="text-xs text-muted-foreground">
              {visibleOpen} item{visibleOpen === 1 ? "" : "s"} need your attention
            </p>
          </div>
          {user.role === "auditor" && (
            <Badge variant="outline" className="text-[11px]">Read only</Badge>
          )}
        </div>

        <Tabs value={tab} onValueChange={(v) => setTab(v as QueueTab)}>
          <TabsList>
            <TabsTrigger value="all">All · {tabCounts.all}</TabsTrigger>
            <TabsTrigger value="transactions">Transactions · {tabCounts.transactions}</TabsTrigger>
            <TabsTrigger value="onboarding">Onboarding · {tabCounts.onboarding}</TabsTrigger>
            <TabsTrigger value="sanctions">Sanctions · {tabCounts.sanctions}</TabsTrigger>
            <TabsTrigger value="escalated">Escalated · {tabCounts.escalated}</TabsTrigger>
          </TabsList>
        </Tabs>

        {meFilterActive && (
          <div className="flex items-center gap-2 rounded-md bg-primary/10 px-2.5 py-1.5 text-xs">
            <span>Showing items assigned to you</span>
            <Button variant="ghost" size="sm" className="ml-auto h-6 gap-1 px-2 text-xs" onClick={() => setMeFilterActive(false)}>
              <X className="h-3 w-3" /> Clear filter
            </Button>
          </div>
        )}

        <Card className="p-3">
          <div className="flex flex-wrap items-center gap-2">
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search title, subject, assignee…"
              className="h-9 w-[260px]"
            />
            <Select value={statusFilter} onValueChange={(v) => setStatusFilter(v as CaseStatus | "all")}>
              <SelectTrigger className="h-9 w-[170px]"><SelectValue placeholder="Status" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All statuses</SelectItem>
                {STATUSES.map((s) => <SelectItem key={s} value={s}>{s.replace(/_/g, " ")}</SelectItem>)}
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
                  <th className="px-3 py-2 font-medium">Subject</th>
                  <th className="px-3 py-2 font-medium">Assigned to</th>
                  <th className="px-3 py-2 font-medium">Status</th>
                  <th className="px-3 py-2 font-medium">Due date</th>
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
                    <td className="px-3 py-2 text-xs">{subjectName(c)}</td>
                    <td className="px-3 py-2 text-xs">{c.assigned_to}</td>
                    <td className="px-3 py-2"><StatusPill value={c.status} /></td>
                    <td className="px-3 py-2 text-xs text-muted-foreground">{format(new Date(c.due_date), "yyyy-MM-dd")}</td>
                  </tr>
                ))}
                {filtered.length === 0 && (
                  <tr><td colSpan={7} className="p-8 text-center text-sm text-muted-foreground">No items match.</td></tr>
                )}
              </tbody>
            </table>
          </div>
        </Card>
      </div>

      <aside className="hidden w-[480px] shrink-0 border-l bg-background xl:block">
        {selected ? (
          <CaseDetail value={selected} onChanged={refresh} extraActions={sanctionsActions} />
        ) : (
          <div className="flex h-full flex-col items-center justify-center gap-2 p-8 text-center text-sm text-muted-foreground">
            <div className="flex h-10 w-10 items-center justify-center rounded-full bg-muted">
              <Inbox className="h-4 w-4" />
            </div>
            Select an item to view its details.
          </div>
        )}
      </aside>
    </div>
  );
}
