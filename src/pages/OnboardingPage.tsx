import { useEffect, useMemo, useState } from "react";
import { Flag, Mail, UserPlus } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import {
  listAccountHolders, listDocuments, listKycRequirements, listTransactions,
  updateAccountHolder,
} from "@/api";
import type {
  AccountHolderResponse, DocumentResponse, KycRequirementResponse, KycStatus,
  TransactionResponse,
} from "@/api/types";
import { StatusPill } from "@/components/status-pill";
import { toast } from "@/hooks/use-toast";
import { toast as sonnerToast } from "sonner";
import { cn } from "@/lib/utils";
import { shortId } from "@/lib/money";
import { useRuleHits } from "@/hooks/use-rule-hits";
import { RuleHitBanner } from "@/components/rules/rule-hit-banner";
import { CasesSection } from "@/components/cases/cases-section";
import { CreateFlagDialog } from "@/components/cases/create-flag-dialog";
import { usePermission } from "@/hooks/use-permission";
import { OutreachTab } from "@/components/outreach/outreach-tab";
import { OutreachComposer } from "@/components/outreach/outreach-composer";
import { useAuditLogger } from "@/hooks/use-audit-logger";
import {
  DaysWaitingBadge, DocumentChecklist, OnboardingDecision, type ChecklistDoc,
} from "@/components/onboarding/document-checklist";
import { seedChecklist } from "@/components/onboarding/checklist-seed";
import {
  DetailPanel, Field, PanelSection, type DetailPanelTab,
} from "@/components/detail-panel/detail-panel";
import { AssignDialog, TEAM_MEMBERS } from "@/components/detail-panel/assign-dialog";

const KYC_FILTERS: Array<KycStatus | "all"> = ["all", "not_started", "in_progress", "approved", "rejected", "on_hold"];

// Pre-seeded assignments by holder id
const SEEDED_ASSIGNMENTS: Record<string, string> = {};
const seedAssign = (n: number, who: string) => {
  const id = `${n.toString(16).padStart(8, "0")}-aaaa-bbbb-cccc-${n.toString(16).padStart(12, "0")}`;
  SEEDED_ASSIGNMENTS[id] = who;
};
seedAssign(103, "Ana Martins");      // Nordic Freight
seedAssign(107, "James Osei");       // Maria González
seedAssign(105, "Priya Nair");       // Cairo Trade
seedAssign(104, "James Osei");       // Jin Wei
seedAssign(109, "Ana Martins");      // Volga
seedAssign(102, "Unassigned");       // Lumière

// Limit onboarding queue to in-progress / not_started / on_hold / rejected
const ONBOARDING_STATUSES: KycStatus[] = ["not_started", "in_progress", "on_hold", "rejected", "approved"];

export default function OnboardingPage() {
  const [holders, setHolders] = useState<AccountHolderResponse[]>([]);
  const [filter, setFilter] = useState<KycStatus | "all">("all");
  const [search, setSearch] = useState("");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [kycs, setKycs] = useState<KycRequirementResponse[]>([]);
  const [docs, setDocs] = useState<DocumentResponse[]>([]);
  const [assignments, setAssignments] = useState<Record<string, string>>(SEEDED_ASSIGNMENTS);
  const [openCaseDialog, setOpenCaseDialog] = useState(false);
  const [outreachOpen, setOutreachOpen] = useState(false);
  const [assignOpen, setAssignOpen] = useState(false);
  const [allTransactions, setAllTransactions] = useState<TransactionResponse[]>([]);
  const [checklists, setChecklists] = useState<Record<string, ChecklistDoc[]>>({});
  const [activeTab, setActiveTab] = useState("overview");
  const canReassign = usePermission("onboarding.approve");
  const logAudit = useAuditLogger();

  useEffect(() => {
    listAccountHolders().then((all) => {
      // Show only those that are part of onboarding queue (any kyc status)
      const queue = all.filter((h) => ONBOARDING_STATUSES.includes(h.kyc_status));
      setHolders(queue);
      if (!selectedId && queue[0]) setSelectedId(queue[0].id);
    });
    listTransactions().then(setAllTransactions);
  }, []);

  useEffect(() => {
    if (!selectedId) return;
    listKycRequirements(selectedId).then(setKycs);
    listDocuments(selectedId).then(setDocs);
  }, [selectedId]);

  const selected = holders.find((h) => h.id === selectedId);

  useEffect(() => {
    if (!selected || checklists[selected.id]) return;
    const volume = allTransactions
      .filter((t) => t.account_holder_id === selected.id)
      .reduce((sum, t) => sum + (t.amount ?? 0), 0);
    setChecklists((prev) => ({ ...prev, [selected.id]: seedChecklist(selected, volume) }));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedId, holders.length, allTransactions.length]);

  const filtered = useMemo(() => {
    return holders.filter((h) => {
      if (filter !== "all" && h.kyc_status !== filter) return false;
      if (search && !h.display_name.toLowerCase().includes(search.toLowerCase())) return false;
      return true;
    });
  }, [holders, filter, search]);

  const handleHolderUpdate = async (patch: Partial<AccountHolderResponse>) => {
    if (!selected) return;
    const next = await updateAccountHolder(selected.id, patch);
    setHolders((prev) => prev.map((h) => (h.id === next.id ? next : h)));
    if (patch.kyc_status === "approved") {
      logAudit({ action_type: "onboarding.approved", resource_type: "account_holder", resource_id: next.id, description: `Approved KYC for ${next.display_name}`, metadata: {} });
    } else if (patch.kyc_status === "rejected") {
      logAudit({ action_type: "onboarding.rejected", resource_type: "account_holder", resource_id: next.id, description: `Rejected KYC for ${next.display_name}`, metadata: {} });
    }
    toast({ title: "Account holder updated", description: `PUT /api/account-holders/${shortId(next.id, 6)}` });
  };

  return (
    <div className="flex h-full">
      <div className="flex w-[360px] shrink-0 flex-col border-r bg-background">
        <div className="border-b p-3">
          <h1 className="text-lg font-semibold tracking-tight">Onboarding queue</h1>
          <p className="text-xs text-muted-foreground">{filtered.length} of {holders.length} account holders</p>
          <div className="mt-2 flex gap-2">
            <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search…" className="h-8" />
            <Select value={filter} onValueChange={(v) => setFilter(v as KycStatus | "all")}>
              <SelectTrigger className="h-8 w-[130px]"><SelectValue /></SelectTrigger>
              <SelectContent>
                {KYC_FILTERS.map((f) => <SelectItem key={f} value={f}>{f === "all" ? "All KYC" : f.replace(/_/g, " ")}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto">
          {filtered.map((h) => {
            const assignee = assignments[h.id] ?? "Unassigned";
            return (
              <button
                key={h.id}
                onClick={() => setSelectedId(h.id)}
                className={cn(
                  "flex w-full flex-col gap-1.5 border-b px-3 py-2.5 text-left transition hover:bg-muted/50",
                  selectedId === h.id && "bg-primary/5",
                )}
              >
                <div className="flex items-center gap-2">
                  <span className="truncate text-sm font-medium">{h.display_name}</span>
                  <span className="ml-auto"><StatusPill value={h.kyc_status} /></span>
                </div>
                <div className="flex flex-wrap items-center gap-1.5 text-[11px] text-muted-foreground">
                  <Badge variant="outline" className="h-4 px-1.5 text-[10px] capitalize">{h.entity_type}</Badge>
                  <span>{h.country}</span>
                  <StatusPill value={h.risk_level} />
                  <DaysWaitingBadge since={h.inserted_at} />
                </div>
                <div className={cn("text-[11px]", assignee === "Unassigned" ? "text-muted-foreground italic" : "text-foreground")}>
                  {assignee === "Unassigned" ? "Unassigned" : `Assigned to ${assignee}`}
                </div>
              </button>
            );
          })}
          {filtered.length === 0 && (
            <div className="p-6 text-center text-xs text-muted-foreground">No matching holders.</div>
          )}
        </div>
      </div>

      {selected ? (
        <div className="min-w-0 flex-1">
          <OnboardingDetail
            holder={selected}
            kycs={kycs}
            docs={docs}
            allTransactions={allTransactions}
            checklist={checklists[selected.id] ?? []}
            onChecklistChange={(key, patch) => {
              setChecklists((prev) => ({
                ...prev,
                [selected.id]: prev[selected.id].map((d) => (d.key === key ? { ...d, ...patch } : d)),
              }));
              if (patch.status) sonnerToast.success(`Document ${patch.status}`, { description: key.replace(/_/g, " ") });
            }}
            assignee={assignments[selected.id] ?? "Unassigned"}
            onAssign={(v) => {
              setAssignments((prev) => ({ ...prev, [selected.id]: v }));
            }}
            canReassign={canReassign}
            onApprove={() => handleHolderUpdate({ kyc_status: "approved" })}
            onReject={(reason) => {
              handleHolderUpdate({ kyc_status: "rejected" });
              sonnerToast.success("Onboarding rejected", { description: reason });
            }}
            onRequestEdd={() => {
              handleHolderUpdate({ kyc_status: "on_hold" });
              sonnerToast.success("EDD requested", { description: "Escalated to enhanced due diligence." });
            }}
            activeTab={activeTab}
            onTabChange={setActiveTab}
            onOpenCase={() => setOpenCaseDialog(true)}
            onOpenOutreach={() => setOutreachOpen(true)}
            onOpenAssign={() => setAssignOpen(true)}
          />
          <CreateFlagDialog
            open={openCaseDialog}
            onOpenChange={setOpenCaseDialog}
            transactionId={selected.id}
            defaultTitle={`Onboarding review · ${selected.display_name}`}
          />
          <OutreachComposer
            open={outreachOpen}
            onOpenChange={setOutreachOpen}
            subjectType="account_holder"
            subjectId={selected.id}
            customerName={selected.display_name}
            customerEmail={selected.email ?? ""}
            onSent={() => setActiveTab("outreach")}
          />
          <AssignDialog
            open={assignOpen}
            onOpenChange={setAssignOpen}
            current={assignments[selected.id]}
            resourceLabel={selected.display_name}
            onAssign={(v) => setAssignments((prev) => ({ ...prev, [selected.id]: v }))}
          />
        </div>
      ) : (
        <div className="flex flex-1 items-center justify-center text-sm text-muted-foreground">
          Select an account holder.
        </div>
      )}
    </div>
  );
}

interface DetailProps {
  holder: AccountHolderResponse;
  kycs: KycRequirementResponse[];
  docs: DocumentResponse[];
  allTransactions: TransactionResponse[];
  checklist: ChecklistDoc[];
  onChecklistChange: (key: string, patch: Partial<ChecklistDoc>) => void;
  assignee: string;
  onAssign: (v: string) => void;
  canReassign: boolean;
  onApprove: () => void;
  onReject: (reason: string) => void;
  onRequestEdd: () => void;
  activeTab: string;
  onTabChange: (id: string) => void;
  onOpenCase: () => void;
  onOpenOutreach: () => void;
  onOpenAssign: () => void;
}

function OnboardingDetail({
  holder, kycs, docs, checklist, onChecklistChange, assignee, onAssign,
  canReassign, onApprove, onReject, onRequestEdd, activeTab, onTabChange,
  onOpenCase, onOpenOutreach, onOpenAssign,
}: DetailProps) {
  const ruleHits = useRuleHits("account_holder", holder.id);
  const allApproved = checklist.length > 0 && checklist.every((d) => d.status === "approved");

  const tabs: DetailPanelTab[] = [
    {
      id: "overview",
      label: "Overview",
      render: () => (
        <>
          <PanelSection title="Account holder">
            <Field label="legal_name">{holder.legal_name}</Field>
            <Field label="entity_type">{holder.entity_type}</Field>
            <Field label="country">{holder.country}</Field>
            <Field label="risk_level"><StatusPill value={holder.risk_level} /></Field>
            <Field label="kyc_status"><StatusPill value={holder.kyc_status} /></Field>
            <Field label="email">{holder.email ?? "—"}</Field>
            <Field label="days_waiting"><DaysWaitingBadge since={holder.inserted_at} /></Field>
            <Field label="assigned_to">
              {canReassign ? (
                <Select value={assignee} onValueChange={onAssign}>
                  <SelectTrigger className="h-7 w-[180px] text-xs"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {TEAM_MEMBERS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
                  </SelectContent>
                </Select>
              ) : (
                <span>{assignee}</span>
              )}
            </Field>
          </PanelSection>

          <PanelSection title="Decision">
            <OnboardingDecision
              allApproved={allApproved}
              onApprove={onApprove}
              onReject={onReject}
              onRequestEdd={onRequestEdd}
            />
          </PanelSection>
        </>
      ),
    },
    {
      id: "documents",
      label: "Documents",
      render: () => (
        checklist.length > 0 ? (
          <DocumentChecklist
            holder={holder}
            docs={checklist}
            customerEmail={holder.email ?? ""}
            onChange={onChecklistChange}
          />
        ) : (
          <div className="text-xs text-muted-foreground">No checklist available.</div>
        )
      ),
    },
    {
      id: "kyc",
      label: "KYC",
      render: () => (
        <>
          <PanelSection title="KYC overview">
            <Field label="kyc_status"><StatusPill value={holder.kyc_status} /></Field>
            <Field label="risk_level"><StatusPill value={holder.risk_level} /></Field>
            <Field label="pep_status">{holder.risk_level === "high" || holder.risk_level === "critical" ? "Potential PEP — review" : "Not flagged"}</Field>
            <Field label="sanctions">
              <StatusPill value={checklist.find((d) => d.key === "sanctions")?.status === "approved" ? "clear" : checklist.find((d) => d.key === "sanctions")?.status ?? "pending"} />
            </Field>
            <Field label="rationale">
              {holder.risk_level === "critical" ? "Sanctioned jurisdiction exposure" :
               holder.risk_level === "high" ? "Elevated risk geography or volume" :
               holder.risk_level === "medium" ? "Standard monitoring" : "Low-risk profile"}
            </Field>
          </PanelSection>
          <PanelSection title="Open KYC requirements">
            {kycs.length === 0 ? (
              <div className="text-xs text-muted-foreground">No KYC requirements on file.</div>
            ) : (
              <ul className="-mx-3 -my-3">
                {kycs.map((k) => (
                  <li key={k.id} className="flex items-center gap-2 border-b px-3 py-2 text-xs last:border-b-0">
                    <span className="font-medium capitalize">{k.requirement_type.replace(/_/g, " ")}</span>
                    <span className="ml-auto"><StatusPill value={k.status} /></span>
                  </li>
                ))}
              </ul>
            )}
          </PanelSection>
        </>
      ),
    },
    {
      id: "outreach",
      label: "Outreach",
      render: () => (
        <OutreachTab
          subjectType="account_holder"
          subjectId={holder.id}
          customerName={holder.display_name}
          customerEmail={holder.email ?? ""}
        />
      ),
    },
    {
      id: "cases",
      label: "Cases",
      render: () => <CasesSection sourceId={holder.id} title="Cases for this holder" />,
    },
  ];

  return (
    <DetailPanel
      title={holder.legal_name}
      statusValue={holder.kyc_status}
      subtitle={
        <span className="capitalize">
          {holder.entity_type} · {holder.country} · Assigned to <span className="font-medium not-italic text-foreground">{assignee}</span>
        </span>
      }
      actions={[
        { id: "flag", label: "Create flag", icon: Flag, permission: "transaction.create_flag", onClick: onOpenCase },
        { id: "outreach", label: "Request info", icon: Mail, permission: "transaction.outreach", onClick: onOpenOutreach },
        { id: "assign", label: assignee === "Unassigned" ? "Assign" : assignee, icon: UserPlus, permission: "onboarding.approve", onClick: onOpenAssign },
      ]}
      banner={<RuleHitBanner hits={ruleHits} onView={() => onTabChange("kyc")} />}
      tabs={tabs}
      activeTab={activeTab}
      onTabChange={onTabChange}
    />
  );
}
