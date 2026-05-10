import { useEffect, useState } from "react";
import { format, formatDistanceToNow } from "date-fns";
import { CheckCircle2, FileText, Mail, ShieldX, AlertCircle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";
import { OutreachComposer } from "@/components/outreach/outreach-composer";
import { usePermission } from "@/hooks/use-permission";
import type { AccountHolderResponse } from "@/api/types";

export type DocStatus = "required" | "submitted" | "approved" | "rejected" | "expired";

export interface ChecklistDoc {
  key: string;
  label: string;
  status: DocStatus;
  filename?: string;
  uploaded_at?: string;
  outreach_doc_type?: string;
  conditional_note?: string;
}

interface ChecklistRequirements {
  totalTransactionVolume?: number;
}

export function getRequiredDocs(
  holder: AccountHolderResponse,
  reqs: ChecklistRequirements = {},
): ChecklistDoc[] {
  if (holder.entity_type === "business") {
    const items: ChecklistDoc[] = [
      { key: "incorporation", label: "Certificate of Incorporation", status: "required", outreach_doc_type: "Business Registration" },
      { key: "registered_address", label: "Proof of Registered Address", status: "required", outreach_doc_type: "Proof of Address" },
      { key: "ubo_declaration", label: "UBO Declaration (>25%)", status: "required", outreach_doc_type: "Beneficial Ownership Disclosure" },
      { key: "ubo_id", label: "Government-issued ID for each UBO", status: "required", outreach_doc_type: "Government-issued ID" },
    ];
    if ((reqs.totalTransactionVolume ?? 0) > 100_000) {
      items.push({
        key: "audited_financials",
        label: "Latest audited financials",
        status: "required",
        outreach_doc_type: "Bank Statement",
        conditional_note: "Required: transaction volume > $100k",
      });
    }
    items.push({ key: "sanctions", label: "Sanctions screening result", status: "required" });
    return items;
  }
  const items: ChecklistDoc[] = [
    { key: "photo_id", label: "Government-issued photo ID", status: "required", outreach_doc_type: "Government-issued ID" },
    { key: "proof_of_address", label: "Proof of Address (< 3 months)", status: "required", outreach_doc_type: "Proof of Address" },
    { key: "sanctions", label: "Sanctions screening result", status: "required" },
  ];
  if (holder.risk_level === "high" || holder.risk_level === "prohibited") {
    items.push({
      key: "source_of_funds",
      label: "Source of funds declaration",
      status: "required",
      outreach_doc_type: "Source of Funds Statement",
      conditional_note: "Required: risk level high",
    });
  }
  return items;
}

const STATUS_VARIANTS: Record<DocStatus, string> = {
  required: "bg-muted text-muted-foreground",
  submitted: "bg-blue-100 text-blue-700 dark:bg-blue-950 dark:text-blue-300",
  approved: "bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-300",
  rejected: "bg-rose-100 text-rose-700 dark:bg-rose-950 dark:text-rose-300",
  expired: "bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-300",
};

interface Props {
  holder: AccountHolderResponse;
  docs: ChecklistDoc[];
  onChange: (key: string, patch: Partial<ChecklistDoc>) => void;
  customerEmail: string;
}

export function DocumentChecklist({ holder, docs, onChange, customerEmail }: Props) {
  const canDecide = usePermission("onboarding.approve");
  const canRequest = usePermission("onboarding.request_docs");
  const [outreach, setOutreach] = useState<{ open: boolean; docTypes: string[] }>({ open: false, docTypes: [] });

  return (
    <Card className="p-0">
      <div className="flex items-center justify-between border-b px-4 py-2.5">
        <div className="text-sm font-medium">Document checklist</div>
        <span className="text-xs text-muted-foreground">
          {docs.filter((d) => d.status === "approved").length} / {docs.length} approved
        </span>
      </div>
      <ul>
        {docs.map((d) => (
          <li key={d.key} className="flex items-center gap-3 border-b px-4 py-3 last:border-b-0">
            <FileText className="h-4 w-4 shrink-0 text-muted-foreground" />
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <span className="text-sm font-medium">{d.label}</span>
                <Badge variant="secondary" className={cn("h-5 text-[10px] capitalize", STATUS_VARIANTS[d.status])}>
                  {d.status}
                </Badge>
                {d.conditional_note && (
                  <span className="text-[10px] text-muted-foreground">· {d.conditional_note}</span>
                )}
              </div>
              {d.filename && (
                <div className="mt-0.5 flex items-center gap-2 text-[11px] text-muted-foreground">
                  <button
                    onClick={() => window.alert(`Preview: ${d.filename}`)}
                    className="text-primary hover:underline"
                  >
                    {d.filename}
                  </button>
                  {d.uploaded_at && <span>· uploaded {format(new Date(d.uploaded_at), "yyyy-MM-dd")}</span>}
                </div>
              )}
            </div>
            <div className="flex shrink-0 items-center gap-1.5">
              {canDecide && d.status !== "approved" && (
                <Button
                  size="sm"
                  variant="outline"
                  className="h-7 gap-1 text-xs"
                  onClick={() => onChange(d.key, { status: "approved" })}
                >
                  <CheckCircle2 className="h-3 w-3" /> Approve
                </Button>
              )}
              {canDecide && d.status !== "rejected" && (
                <Button
                  size="sm"
                  variant="outline"
                  className="h-7 gap-1 text-xs"
                  onClick={() => onChange(d.key, { status: "rejected" })}
                >
                  <ShieldX className="h-3 w-3" /> Reject
                </Button>
              )}
              {canRequest && d.outreach_doc_type && d.status !== "approved" && (
                <Button
                  size="sm"
                  variant="ghost"
                  className="h-7 gap-1 text-xs"
                  onClick={() => setOutreach({ open: true, docTypes: [d.outreach_doc_type!] })}
                >
                  <Mail className="h-3 w-3" /> Request
                </Button>
              )}
            </div>
          </li>
        ))}
      </ul>

      <OutreachComposer
        open={outreach.open}
        onOpenChange={(v) => setOutreach((s) => ({ ...s, open: v }))}
        subjectType="account_holder"
        subjectId={holder.id}
        customerName={holder.display_name}
        customerEmail={customerEmail}
        prefilledTemplate="additional_documentation"
        prefilledDocs={outreach.docTypes}
      />
    </Card>
  );
}

interface DecisionProps {
  allApproved: boolean;
  onApprove: () => void;
  onReject: (reason: string) => void;
  onRequestEdd: () => void;
}

export function OnboardingDecision({ allApproved, onApprove, onReject, onRequestEdd }: DecisionProps) {
  const canDecide = usePermission("onboarding.approve");
  const [rejectOpen, setRejectOpen] = useState(false);
  const [reason, setReason] = useState("");

  if (!canDecide) return null;

  return (
    <Card className="p-4">
      <div className="mb-3 text-sm font-medium">Decision</div>
      <div className="flex flex-wrap gap-2">
        <TooltipProvider>
          <Tooltip>
            <TooltipTrigger asChild>
              <span>
                <Button
                  size="sm"
                  className="gap-1.5 bg-emerald-600 text-white hover:bg-emerald-700"
                  disabled={!allApproved}
                  onClick={onApprove}
                >
                  <CheckCircle2 className="h-3.5 w-3.5" /> Approve onboarding
                </Button>
              </span>
            </TooltipTrigger>
            {!allApproved && (
              <TooltipContent>All required documents must be approved first.</TooltipContent>
            )}
          </Tooltip>
        </TooltipProvider>

        <Button
          size="sm"
          variant="destructive"
          className="gap-1.5"
          onClick={() => setRejectOpen(true)}
        >
          <ShieldX className="h-3.5 w-3.5" /> Reject onboarding
        </Button>

        <Button size="sm" variant="outline" className="gap-1.5" onClick={onRequestEdd}>
          <AlertCircle className="h-3.5 w-3.5" /> Request EDD
        </Button>
      </div>

      {rejectOpen && (
        <div className="mt-3 space-y-2 rounded-md border bg-muted/30 p-3">
          <label className="text-xs font-medium">Rejection reason (required)</label>
          <textarea
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            rows={3}
            className="w-full rounded-md border bg-background p-2 text-sm"
            placeholder="Why is this onboarding rejected?"
          />
          <div className="flex justify-end gap-2">
            <Button size="sm" variant="ghost" onClick={() => { setRejectOpen(false); setReason(""); }}>
              Cancel
            </Button>
            <Button
              size="sm"
              variant="destructive"
              disabled={!reason.trim()}
              onClick={() => {
                onReject(reason.trim());
                setReason("");
                setRejectOpen(false);
              }}
            >
              Confirm rejection
            </Button>
          </div>
        </div>
      )}
    </Card>
  );
}

export function DaysWaitingBadge({ since }: { since: string }) {
  const days = Math.floor((Date.now() - new Date(since).getTime()) / 86_400_000);
  const tone =
    days > 5 ? "bg-rose-100 text-rose-700 dark:bg-rose-950 dark:text-rose-300"
      : days > 2 ? "bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-300"
      : "bg-muted text-muted-foreground";
  return (
    <Badge variant="secondary" className={cn("h-5 text-[10px]", tone)}>
      Waiting {days} day{days === 1 ? "" : "s"}
    </Badge>
  );
}

export function lastUpdatedRelative(date: string) {
  return formatDistanceToNow(new Date(date), { addSuffix: true });
}
