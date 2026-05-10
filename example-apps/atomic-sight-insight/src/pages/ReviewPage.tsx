import { useEffect, useMemo, useState } from "react";
import { format } from "date-fns";
import { Briefcase, Building2, RefreshCcw, ShieldCheck, ShieldOff, User } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import {
  listComplianceScreenings, listSanctionsMatches, screenAccountHolder, screenBeneficialOwner, screenCounterparty,
  updateComplianceScreening, updateCounterparty, updateSanctionsMatch,
} from "@/api";
import { accountHolders, beneficialOwners, counterparties } from "@/data/fixtures";
import type {
  ComplianceScreeningResponse, CounterpartyResponse, SanctionsMatchResponse, ScreeningStatus,
} from "@/api/types";
import { StatusPill } from "@/components/status-pill";
import { toast } from "@/hooks/use-toast";
import { toast as sonnerToast } from "sonner";
import { cn } from "@/lib/utils";
import { createCase, listCasesBySource, subscribeCases, type Case } from "@/api/cases";
import { useAuditLogger } from "@/hooks/use-audit-logger";

const FILTERS: Array<ScreeningStatus | "all"> = ["all", "match", "potential_match", "review", "clear"];

const subjectLabel = (s: ComplianceScreeningResponse) => {
  switch (s.subject_type) {
    case "account_holder": return accountHolders.find((a) => a.id === s.subject_id)?.display_name ?? "Account holder";
    case "counterparty": return counterparties.find((c) => c.id === s.subject_id)?.display_name ?? "Counterparty";
    case "beneficial_owner": return beneficialOwners.find((b) => b.id === s.subject_id)?.full_name ?? "Beneficial owner";
  }
};

const REVIEW_ASSIGNEES = ["Ana Martins", "James Osei", "Priya Nair"];

export default function ReviewPage() {
  const [screenings, setScreenings] = useState<ComplianceScreeningResponse[]>([]);
  const [matches, setMatches] = useState<SanctionsMatchResponse[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [filter, setFilter] = useState<ScreeningStatus | "all">("match");
  const [working, setWorking] = useState(false);
  const [allCases, setAllCases] = useState<Case[]>([]);
  const [assignDialogFor, setAssignDialogFor] = useState<ComplianceScreeningResponse | null>(null);
  const [assignTo, setAssignTo] = useState<string>(REVIEW_ASSIGNEES[0]);
  const [assignPriority, setAssignPriority] = useState<"critical" | "high" | "medium" | "low">("high");
  const reviewLog = useAuditLogger();

  useEffect(() => {
    listComplianceScreenings().then((s) => {
      setScreenings(s);
      const first = s.find((x) => x.status !== "clear");
      if (first) setSelectedId(first.id);
    });
  }, []);

  useEffect(() => {
    if (!selectedId) { setMatches([]); return; }
    listSanctionsMatches(selectedId).then(setMatches);
  }, [selectedId]);

  useEffect(() => {
    let alive = true;
    const refresh = async () => {
      const allLists = await Promise.all(screenings.map((s) => listCasesBySource(s.subject_id)));
      if (!alive) return;
      setAllCases(allLists.flat());
    };
    refresh();
    const unsub = subscribeCases(refresh);
    return () => { alive = false; unsub(); };
  }, [screenings]);

  const caseForScreening = (s: ComplianceScreeningResponse) =>
    allCases.find((c) => c.source_id === s.subject_id && c.type === "sanctions_match");

  const submitAssign = async () => {
    if (!assignDialogFor) return;
    const s = assignDialogFor;
    const created = await createCase({
      type: "sanctions_match",
      status: "open",
      priority: assignPriority,
      title: `Sanctions match · ${subjectLabel(s)}`,
      description: `Screening ${s.id.slice(0, 6)} from ${s.provider} returned status "${s.status}".`,
      source_id: s.subject_id,
      source_type: s.subject_type === "counterparty" ? "account_holder" : "account_holder",
      assigned_to: assignTo,
      due_date: new Date(Date.now() + 2 * 86_400_000).toISOString(),
    });
    reviewLog({
      action_type: "case.created",
      resource_type: "case",
      resource_id: created.id,
      description: `Created sanctions match case for ${subjectLabel(s)} assigned to ${assignTo}`,
      metadata: { type: "sanctions_match", screening_id: s.id },
    });
    sonnerToast.success("Case assigned", { description: `${subjectLabel(s)} → ${assignTo}` });
    setAssignDialogFor(null);
  };

  const filtered = useMemo(
    () => (filter === "all" ? screenings : screenings.filter((s) => s.status === filter))
      .sort((a, b) => +new Date(b.screened_at) - +new Date(a.screened_at)),
    [screenings, filter],
  );

  const selected = screenings.find((s) => s.id === selectedId);

  const subjectCp = (sc: ComplianceScreeningResponse | undefined): CounterpartyResponse | undefined =>
    sc?.subject_type === "counterparty" ? counterparties.find((c) => c.id === sc.subject_id) : undefined;

  const handleRescreen = async () => {
    if (!selected) return;
    setWorking(true);
    try {
      const fn = selected.subject_type === "account_holder" ? screenAccountHolder
        : selected.subject_type === "counterparty" ? screenCounterparty
        : screenBeneficialOwner;
      const created = await fn(selected.subject_id);
      setScreenings((prev) => [created, ...prev]);
      setSelectedId(created.id);
      toast({ title: "Re-screened", description: `POST /api/compliance-screenings/screen-${selected.subject_type.replace("_", "-")}` });
    } finally {
      setWorking(false);
    }
  };

  const handleCounterpartyStatus = async (status: CounterpartyResponse["status"]) => {
    const cp = subjectCp(selected);
    if (!cp) return;
    await updateCounterparty(cp.id, { status });
    toast({ title: `Counterparty ${status}`, description: `PUT /api/counterparties/${cp.id.slice(0, 6)}` });
    // local refresh of cp displayed
    setScreenings((s) => [...s]); // trigger re-render
  };

  return (
    <div className="flex h-full">
      <div className="flex w-[360px] shrink-0 flex-col border-r bg-background">
        <div className="border-b p-3">
          <h1 className="text-lg font-semibold tracking-tight">Review queue</h1>
          <p className="text-xs text-muted-foreground">Blocked and potential-match screenings.</p>
          <div className="mt-2 flex gap-2">
            <Select value={filter} onValueChange={(v) => setFilter(v as ScreeningStatus | "all")}>
              <SelectTrigger className="h-8"><SelectValue /></SelectTrigger>
              <SelectContent>
                {FILTERS.map((f) => <SelectItem key={f} value={f}>{f === "all" ? "All" : f.replace(/_/g, " ")}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto">
          {filtered.map((s) => {
            const linkedCase = caseForScreening(s);
            return (
              <div
                key={s.id}
                className={cn(
                  "flex w-full flex-col gap-1 border-b px-3 py-2.5 text-left transition",
                  selectedId === s.id ? "bg-primary/5" : "hover:bg-muted/50",
                )}
              >
                <button onClick={() => setSelectedId(s.id)} className="flex w-full items-center gap-2 text-left">
                  {s.subject_type === "counterparty" ? <Building2 className="h-3.5 w-3.5 text-muted-foreground" /> : <User className="h-3.5 w-3.5 text-muted-foreground" />}
                  <span className="truncate text-sm font-medium">{subjectLabel(s)}</span>
                  <span className="ml-auto"><StatusPill value={s.status} /></span>
                </button>
                <div className="text-[11px] text-muted-foreground">
                  {s.provider} · {format(new Date(s.screened_at), "yyyy-MM-dd HH:mm")}
                </div>
                <div className="mt-1 flex items-center gap-2">
                  {linkedCase ? (
                    <>
                      <span className="text-[11px] text-muted-foreground">{linkedCase.assigned_to}</span>
                      <span className="ml-auto"><StatusPill value={linkedCase.status} /></span>
                    </>
                  ) : (
                    <Button
                      size="sm"
                      variant="outline"
                      className="ml-auto h-7 gap-1.5 text-[11px]"
                      onClick={(e) => { e.stopPropagation(); setAssignDialogFor(s); }}
                    >
                      <Briefcase className="h-3 w-3" /> Assign
                    </Button>
                  )}
                </div>
              </div>
            );
          })}
          {filtered.length === 0 && <div className="p-6 text-center text-xs text-muted-foreground">No matching screenings.</div>}
        </div>
      </div>

      {selected ? (
        <div className="flex min-w-0 flex-1 flex-col gap-3 overflow-y-auto p-4">
          <Card className="p-4">
            <div className="flex items-start gap-3">
              <div>
                <div className="text-xs uppercase tracking-wide text-muted-foreground">Subject · {selected.subject_type.replace(/_/g, " ")}</div>
                <div className="text-lg font-semibold">{subjectLabel(selected)}</div>
                <div className="text-xs text-muted-foreground">Screened by {selected.provider} · {format(new Date(selected.screened_at), "yyyy-MM-dd HH:mm")}</div>
              </div>
              <div className="ml-auto flex flex-col items-end gap-1.5">
                <StatusPill value={selected.status} />
              </div>
            </div>
            <div className="mt-3 flex flex-wrap gap-2">
              <Button size="sm" onClick={handleRescreen} disabled={working} className="gap-1.5">
                <RefreshCcw className={cn("h-3.5 w-3.5", working && "animate-spin")} /> Re-screen
              </Button>
              {selected.subject_type === "counterparty" && (
                <>
                  <Button size="sm" variant="outline" className="gap-1.5" onClick={() => handleCounterpartyStatus("suspended")}>
                    <ShieldOff className="h-3.5 w-3.5" /> Suspend counterparty
                  </Button>
                  <Button size="sm" variant="outline" className="gap-1.5" onClick={() => handleCounterpartyStatus("active")}>
                    <ShieldCheck className="h-3.5 w-3.5" /> Unblock
                  </Button>
                </>
              )}
            </div>
          </Card>

          <Card className="p-0">
            <div className="flex items-center justify-between border-b px-4 py-2.5">
              <div className="text-sm font-medium">Sanctions matches</div>
              <span className="text-xs text-muted-foreground">{matches.length}</span>
            </div>
            {matches.length === 0 ? (
              <div className="px-4 py-8 text-center text-xs text-muted-foreground">No sanctions matches on this screening.</div>
            ) : (
              <ul>
                {matches.map((m) => (
                  <li key={m.id} className="border-b px-4 py-3 last:border-b-0">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-medium">{m.matched_name}</span>
                      <span className="text-xs text-muted-foreground">· {m.list_name}</span>
                      <span className="ml-auto rounded bg-muted px-1.5 py-0.5 font-mono text-[11px]">score {m.score}</span>
                    </div>
                    {m.false_positive_qualifier ? (
                      <div className="mt-1 text-[11px] text-muted-foreground">
                        <span className="font-medium">False positive:</span> {m.false_positive_qualifier} — {m.justification}
                        <span className="ml-1 text-muted-foreground/70">· reviewed by {m.reviewer ?? "—"}</span>
                      </div>
                    ) : (
                      <div className="mt-2">
                        <FalsePositiveDialog
                          match={m}
                          screeningId={selected.id}
                          onSaved={(nextMatch, nextScreening) => {
                            setMatches((prev) => prev.map((x) => (x.id === nextMatch.id ? nextMatch : x)));
                            setScreenings((prev) => prev.map((s) => (s.id === nextScreening.id ? nextScreening : s)));
                          }}
                        />
                      </div>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>
      ) : (
        <div className="flex flex-1 items-center justify-center text-sm text-muted-foreground">Select a screening.</div>
      )}
    </div>
  );
}

function FalsePositiveDialog({
  match, screeningId, onSaved,
}: {
  match: SanctionsMatchResponse;
  screeningId: string;
  onSaved: (m: SanctionsMatchResponse, s: ComplianceScreeningResponse) => void;
}) {
  const [open, setOpen] = useState(false);
  const [qualifier, setQualifier] = useState("name_collision");
  const [reviewer, setReviewer] = useState("alex.officer@alvera.ai");
  const [justification, setJustification] = useState("");
  const [saving, setSaving] = useState(false);
  const logAudit = useAuditLogger();

  const submit = async () => {
    setSaving(true);
    try {
      const nextMatch = await updateSanctionsMatch(match.id, { false_positive_qualifier: qualifier, reviewer, justification });
      const nextScreening = await updateComplianceScreening(screeningId, { status: "clear", reviewer });
      onSaved(nextMatch, nextScreening);
      logAudit({
        action_type: "screening.dispositioned",
        resource_type: "screening",
        resource_id: screeningId,
        description: `Marked screening match as false positive (${qualifier.replace(/_/g, " ")})`,
        metadata: { qualifier, match_id: match.id },
      });
      toast({ title: "Marked false positive", description: `PUT /api/compliance-screenings/${screeningId.slice(0, 6)}` });
      setOpen(false);
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm" variant="outline">Mark false positive</Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Mark as false positive</DialogTitle>
          <DialogDescription>Sets SanctionsMatch.false_positive_qualifier and clears the screening.</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div>
            <Label>Qualifier</Label>
            <Select value={qualifier} onValueChange={setQualifier}>
              <SelectTrigger className="mt-1"><SelectValue /></SelectTrigger>
              <SelectContent>
                {["name_collision", "different_country", "different_dob", "secondary_evidence", "other"].map((q) =>
                  <SelectItem key={q} value={q}>{q.replace(/_/g, " ")}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div>
            <Label>Reviewer</Label>
            <Input value={reviewer} onChange={(e) => setReviewer(e.target.value)} className="mt-1" />
          </div>
          <div>
            <Label>Justification</Label>
            <Textarea value={justification} onChange={(e) => setJustification(e.target.value)} className="mt-1 min-h-[80px]" />
          </div>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={submit} disabled={saving || !justification.trim()}>{saving ? "Saving…" : "Confirm"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
