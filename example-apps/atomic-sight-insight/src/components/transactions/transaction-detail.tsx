import { useEffect, useMemo, useState } from "react";
import { format } from "date-fns";
import { Building2, Flag, Mail, Landmark, ShieldCheck, User, UserPlus } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { toast } from "@/hooks/use-toast";
import {
  getAccountHolder,
  getComplianceScreening,
  getCounterparty,
  getLedgerEntry,
  listBeneficialOwners,
  listDocuments,
  listKycRequirements,
  listLedgerAccountBalances,
  listSanctionsMatches,
  updateTransaction,
} from "@/api";
import type {
  AccountHolderResponse,
  BeneficialOwnerResponse,
  ComplianceScreeningResponse,
  CounterpartyResponse,
  DocumentResponse,
  KycRequirementResponse,
  LedgerAccountBalanceResponse,
  LedgerEntryResponse,
  SanctionsMatchResponse,
  TransactionResponse,
  TransactionStatus,
} from "@/api/types";
import { formatAmount, shortId } from "@/lib/money";
import { StatusPill } from "@/components/status-pill";
import { useRuleHits } from "@/hooks/use-rule-hits";
import { RuleHitBanner } from "@/components/rules/rule-hit-banner";
import { RuleHitsTab } from "@/components/rules/rule-hits-tab";
import { usePermission } from "@/hooks/use-permission";
import { useAuditLogger } from "@/hooks/use-audit-logger";
import { CreateFlagDialog } from "@/components/cases/create-flag-dialog";
import { CasesSection } from "@/components/cases/cases-section";
import { OutreachTab } from "@/components/outreach/outreach-tab";
import { OutreachComposer } from "@/components/outreach/outreach-composer";
import {
  DetailPanel,
  Field,
  PanelSection,
  SectionHeading,
  type DetailPanelTab,
} from "@/components/detail-panel/detail-panel";
import { AssignDialog } from "@/components/detail-panel/assign-dialog";

const STATUSES: TransactionStatus[] = ["pending", "accepted", "settled", "rejected", "reversed", "cancelled"];

export function TransactionDetail({
  tx,
  onUpdated,
}: {
  tx: TransactionResponse;
  onUpdated: (next: TransactionResponse) => void;
}) {
  const [holder, setHolder] = useState<AccountHolderResponse | undefined>();
  const [debtorCp, setDebtorCp] = useState<CounterpartyResponse | undefined>();
  const [creditorCp, setCreditorCp] = useState<CounterpartyResponse | undefined>();
  const [ubos, setUbos] = useState<BeneficialOwnerResponse[]>([]);
  const [kycs, setKycs] = useState<KycRequirementResponse[]>([]);
  const [docs, setDocs] = useState<DocumentResponse[]>([]);
  const [screening, setScreening] = useState<ComplianceScreeningResponse | undefined>();
  const [matches, setMatches] = useState<SanctionsMatchResponse[]>([]);
  const [entry, setEntry] = useState<LedgerEntryResponse | undefined>();
  const [balances, setBalances] = useState<LedgerAccountBalanceResponse[]>([]);
  const [statusDraft, setStatusDraft] = useState<TransactionStatus>(tx.status ?? "pending");
  const [saving, setSaving] = useState(false);
  const [activeTab, setActiveTab] = useState("overview");
  const [assignee, setAssignee] = useState("Unassigned");
  const ruleHits = useRuleHits("transaction", tx.id);
  const canUpdateStatus = usePermission("transaction.update_status");
  const logAudit = useAuditLogger();
  const [flagOpen, setFlagOpen] = useState(false);
  const [outreachOpen, setOutreachOpen] = useState(false);
  const [assignOpen, setAssignOpen] = useState(false);

  useEffect(() => {
    setStatusDraft(tx.status ?? "pending");
  }, [tx.id, tx.status]);

  useEffect(() => {
    let alive = true;
    (async () => {
      const [h, dCp, cCp, ks, ds, sc, le, bal] = await Promise.all([
        getAccountHolder(tx.account_holder_id),
        tx.debtor_counterparty_id ? getCounterparty(tx.debtor_counterparty_id) : Promise.resolve(undefined),
        tx.creditor_counterparty_id ? getCounterparty(tx.creditor_counterparty_id) : Promise.resolve(undefined),
        listKycRequirements(tx.account_holder_id),
        listDocuments(tx.account_holder_id),
        tx.compliance_screening_id ? getComplianceScreening(tx.compliance_screening_id) : Promise.resolve(undefined),
        tx.ledger_entry_id ? getLedgerEntry(tx.ledger_entry_id) : Promise.resolve(undefined),
        listLedgerAccountBalances(),
      ]);
      if (!alive) return;
      setHolder(h); setDebtorCp(dCp); setCreditorCp(cCp);
      setKycs(ks); setDocs(ds); setScreening(sc); setEntry(le); setBalances(bal);
      const cpForUbo = cCp ?? dCp;
      if (cpForUbo) {
        const u = await listBeneficialOwners(cpForUbo.id);
        if (alive) setUbos(u);
      } else setUbos([]);
      if (sc) {
        const m = await listSanctionsMatches(sc.id);
        if (alive) setMatches(m);
      } else setMatches([]);
    })();
    return () => { alive = false; };
  }, [tx.id, tx.account_holder_id, tx.debtor_counterparty_id, tx.creditor_counterparty_id, tx.compliance_screening_id, tx.ledger_entry_id]);

  const handleSave = async () => {
    if (statusDraft === tx.status) return;
    setSaving(true);
    try {
      const next = await updateTransaction(tx.id, { status: statusDraft });
      onUpdated(next);
      logAudit({
        action_type: "transaction.status_updated",
        resource_type: "transaction",
        resource_id: tx.id,
        description: `Updated transaction status from ${tx.status} to ${statusDraft}`,
        metadata: { from: tx.status, to: statusDraft },
      });
      toast({ title: "Transaction updated", description: `Status set to ${statusDraft}.` });
    } catch (e) {
      toast({ title: "Update failed", description: String(e), variant: "destructive" });
    } finally {
      setSaving(false);
    }
  };

  const matchedBalances = useMemo(
    () => balances.filter((b) => b.currency === tx.currency).slice(0, 3),
    [balances, tx.currency],
  );

  const tabs: DetailPanelTab[] = [
    {
      id: "overview",
      label: "Overview",
      render: () => (
        <>
          <PanelSection title={canUpdateStatus ? "Update status" : "Current status"}>
            {canUpdateStatus ? (
              <div className="flex items-center gap-2">
                <Select value={statusDraft} onValueChange={(v) => setStatusDraft(v as TransactionStatus)}>
                  <SelectTrigger className="h-8 flex-1"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {STATUSES.map((s) => <SelectItem key={s} value={s}>{s}</SelectItem>)}
                  </SelectContent>
                </Select>
                <Button size="sm" onClick={handleSave} disabled={saving || statusDraft === tx.status}>
                  {saving ? "Saving…" : "Save"}
                </Button>
              </div>
            ) : (
              <StatusPill value={tx.status} />
            )}
          </PanelSection>
          <PanelSection title="Transaction details">
            <Field label="id">{tx.id}</Field>
            <Field label="type">{tx.transaction_type}</Field>
            <Field label="status_reason_code">{tx.status_reason_code ?? "—"}</Field>
            <Field label="amount">{formatAmount(tx.amount, tx.currency)} ({tx.amount} minor)</Field>
            <Field label="currency">{tx.currency}</Field>
            <Field label="end_to_end_id">{tx.end_to_end_id ?? "—"}</Field>
            <Field label="uetr">{tx.uetr ?? "—"}</Field>
            <Field label="instruction_id">{tx.instruction_id ?? "—"}</Field>
            <Field label="requested_execution_date">{tx.requested_execution_date ?? "—"}</Field>
            <Field label="settlement_date">{tx.settlement_date ?? "—"}</Field>
            <Field label="transaction_external_id">{tx.transaction_external_id ?? "—"}</Field>
            <Field label="inserted_at">{format(new Date(tx.inserted_at), "yyyy-MM-dd HH:mm")}</Field>
            <Field label="updated_at">{format(new Date(tx.updated_at), "yyyy-MM-dd HH:mm")}</Field>
          </PanelSection>
        </>
      ),
    },
    {
      id: "holder",
      label: "Holder",
      render: () => holder ? (
        <PanelSection title={<span className="flex items-center gap-1.5"><User className="h-3 w-3" /> Account holder</span>}>
          <Field label="legal_name">{holder.legal_name}</Field>
          <Field label="entity_type">{holder.entity_type}</Field>
          <Field label="country">{holder.country}</Field>
          <Field label="kyc_status"><StatusPill value={holder.kyc_status} /></Field>
          <Field label="risk_level"><StatusPill value={holder.risk_level} /></Field>
          <Field label="email">{holder.email ?? "—"}</Field>
        </PanelSection>
      ) : <div className="text-xs text-muted-foreground">Loading…</div>,
    },
    {
      id: "counterparty",
      label: "Parties",
      render: () => (
        <>
          {[debtorCp, creditorCp].map((cp, i) => cp ? (
            <PanelSection
              key={cp.id}
              title={<span className="flex items-center gap-1.5"><Building2 className="h-3 w-3" /> {i === 0 ? "Debtor" : "Creditor"}</span>}
              action={<StatusPill value={cp.status} />}
            >
              <Field label="legal_name">{cp.legal_name}</Field>
              <Field label="country">{cp.country}</Field>
              <Field label="external_reference">{cp.external_reference ?? "—"}</Field>
            </PanelSection>
          ) : null)}
          {ubos.length > 0 && (
            <PanelSection title="Beneficial owner chain">
              <ul className="space-y-1.5">
                {ubos.map((u) => (
                  <li key={u.id} className="flex items-center gap-2 text-xs">
                    <span className="font-medium">{u.full_name}</span>
                    <span className="text-muted-foreground">· {u.country}</span>
                    <span className="ml-auto font-mono">{u.ownership_percentage}%</span>
                    {u.is_pep && <span className="rounded bg-warning/20 px-1.5 py-0.5 text-[10px] font-medium text-warning-foreground">PEP</span>}
                  </li>
                ))}
              </ul>
            </PanelSection>
          )}
          {!debtorCp && !creditorCp && <div className="text-xs text-muted-foreground">No counterparties linked.</div>}
        </>
      ),
    },
    {
      id: "kyc",
      label: "KYC",
      render: () => (
        <>
          <PanelSection title="KYC requirements">
            {kycs.length === 0 ? (
              <div className="text-xs text-muted-foreground">No KYC requirements.</div>
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
          <PanelSection title="Documents">
            {docs.length === 0 ? (
              <div className="text-xs text-muted-foreground">No documents.</div>
            ) : (
              <ul className="-mx-3 -my-3">
                {docs.map((d) => (
                  <li key={d.id} className="flex items-center gap-2 border-b px-3 py-2 text-xs last:border-b-0">
                    <span className="font-medium">{d.filename}</span>
                    <span className="text-muted-foreground">· {d.document_type}</span>
                    <span className="ml-auto text-muted-foreground">{format(new Date(d.uploaded_at), "yyyy-MM-dd")}</span>
                  </li>
                ))}
              </ul>
            )}
          </PanelSection>
        </>
      ),
    },
    {
      id: "screening",
      label: "Screen",
      render: () => (
        <>
          {screening ? (
            <PanelSection
              title={<span className="flex items-center gap-1.5"><ShieldCheck className="h-3 w-3" /> Latest screening</span>}
              action={<StatusPill value={screening.status} />}
            >
              <Field label="provider">{screening.provider}</Field>
              <Field label="screened_at">{format(new Date(screening.screened_at), "yyyy-MM-dd HH:mm")}</Field>
              <Field label="reviewer">{screening.reviewer ?? "—"}</Field>
            </PanelSection>
          ) : (
            <div className="text-xs text-muted-foreground">No screening linked.</div>
          )}
          {matches.length > 0 && (
            <PanelSection title="Sanctions matches">
              <ul className="-mx-3 -my-3">
                {matches.map((m) => (
                  <li key={m.id} className="border-b px-3 py-2 text-xs last:border-b-0">
                    <div className="flex items-center gap-2">
                      <span className="font-medium">{m.matched_name}</span>
                      <span className="text-muted-foreground">· {m.list_name}</span>
                      <span className="ml-auto font-mono">{m.score}</span>
                    </div>
                    {m.false_positive_qualifier && (
                      <div className="mt-1 text-[11px] text-muted-foreground">
                        False positive: <span className="font-medium">{m.false_positive_qualifier}</span> — {m.justification}
                      </div>
                    )}
                  </li>
                ))}
              </ul>
            </PanelSection>
          )}
          <PanelSection title={<span className="flex items-center gap-1.5"><Landmark className="h-3 w-3" /> Ledger</span>}>
            {entry ? (
              <Field label={`${entry.direction}`}>{formatAmount(entry.amount, entry.currency)} · posted {format(new Date(entry.posted_at), "yyyy-MM-dd")}</Field>
            ) : (
              <div className="text-xs text-muted-foreground">No ledger entry.</div>
            )}
            {matchedBalances.map((b) => (
              <Field key={b.id} label={b.account_label}>{formatAmount(b.balance, b.currency)}</Field>
            ))}
          </PanelSection>
        </>
      ),
    },
    {
      id: "rules",
      label: "Rules",
      badge: ruleHits.length > 0 ? <span className="ml-1 rounded-full bg-destructive px-1.5 text-[10px] text-destructive-foreground">{ruleHits.length}</span> : undefined,
      render: () => <RuleHitsTab hits={ruleHits} />,
    },
    {
      id: "outreach",
      label: "Outreach",
      render: () => (
        <OutreachTab
          subjectType="transaction"
          subjectId={tx.id}
          customerName={holder?.display_name ?? "Customer"}
          customerEmail={holder?.email ?? ""}
        />
      ),
    },
    {
      id: "cases",
      label: "Cases",
      render: () => <CasesSection sourceId={tx.id} />,
    },
  ];

  return (
    <>
      <DetailPanel
        title={holder?.display_name ?? formatAmount(tx.amount, tx.currency)}
        statusValue={tx.status}
        subtitle={
          <span className="capitalize">
            {tx.transaction_type.replace(/_/g, " ")} · {tx.settlement_date ?? tx.requested_execution_date ?? "—"} · {formatAmount(tx.amount, tx.currency)} · {shortId(tx.id, 10)}
          </span>
        }
        actions={[
          { id: "flag", label: "Create flag", icon: Flag, permission: "transaction.create_flag", onClick: () => setFlagOpen(true) },
          { id: "outreach", label: "Request info", icon: Mail, permission: "transaction.outreach", onClick: () => setOutreachOpen(true) },
          { id: "assign", label: assignee === "Unassigned" ? "Assign" : assignee, icon: UserPlus, permission: "transaction.create_flag", onClick: () => setAssignOpen(true) },
        ]}
        banner={<RuleHitBanner hits={ruleHits} onView={() => setActiveTab("rules")} />}
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
      />

      <CreateFlagDialog
        open={flagOpen}
        onOpenChange={setFlagOpen}
        transactionId={tx.id}
        defaultTitle={`Transaction ${tx.id.slice(0, 8)} flagged`}
      />

      <OutreachComposer
        open={outreachOpen}
        onOpenChange={setOutreachOpen}
        subjectType="transaction"
        subjectId={tx.id}
        customerName={holder?.display_name ?? "Customer"}
        customerEmail={holder?.email ?? ""}
        onSent={() => setActiveTab("outreach")}
      />

      <AssignDialog
        open={assignOpen}
        onOpenChange={setAssignOpen}
        current={assignee}
        resourceLabel="transaction"
        onAssign={setAssignee}
      />
    </>
  );
}
