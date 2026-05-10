import { useEffect, useState } from "react";
import { format, formatDistanceToNow } from "date-fns";
import { Check, Loader2, ShieldAlert, Sparkles, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { approveRecommendation, dismissRecommendation, listRecommendations } from "@/api";
import type { Recommendation } from "@/api/types";
import { toast } from "@/hooks/use-toast";
import { cn } from "@/lib/utils";

const KIND_META: Record<Recommendation["kind"], { label: string; endpoint: string; tone: string }> = {
  add_blocklist_entry: { label: "Add blocklist entry", endpoint: "POST /api/blocklist-entries", tone: "bg-destructive/10 text-destructive" },
  raise_risk_classification: { label: "Raise risk classification", endpoint: "PUT /api/risk-classifications/{id}", tone: "bg-warning/15 text-warning-foreground" },
  request_kyc_document: { label: "Request KYC document", endpoint: "PUT /api/kyc-requirements/{id}", tone: "bg-info/10 text-info" },
  suspend_counterparty: { label: "Suspend counterparty", endpoint: "PUT /api/counterparties/{id}", tone: "bg-destructive/10 text-destructive" },
};

export default function RecommendationsPage() {
  const [recs, setRecs] = useState<Recommendation[]>([]);
  const [working, setWorking] = useState<string | null>(null);

  useEffect(() => { listRecommendations().then(setRecs); }, []);

  const open = recs.filter((r) => r.status === "open");
  const resolved = recs.filter((r) => r.status !== "open");

  const handleApprove = async (id: string) => {
    setWorking(id);
    try {
      const next = await approveRecommendation(id);
      setRecs((prev) => prev.map((r) => (r.id === id ? next : r)));
      toast({ title: "Approved", description: KIND_META[next.kind].endpoint });
    } finally { setWorking(null); }
  };

  const handleDismiss = async (id: string) => {
    setWorking(id);
    try {
      const next = await dismissRecommendation(id);
      setRecs((prev) => prev.map((r) => (r.id === id ? next : r)));
    } finally { setWorking(null); }
  };

  return (
    <div className="flex h-full flex-col gap-4 overflow-y-auto p-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Recommendations</h1>
          <p className="text-xs text-muted-foreground">Streamed from alvera-ai/platform — approval dispatches the corresponding AtomicFi write.</p>
        </div>
        <Badge variant="secondary" className="gap-1.5"><Sparkles className="h-3 w-3" /> {open.length} open</Badge>
      </div>

      <div className="grid grid-cols-1 gap-3 lg:grid-cols-2">
        {open.map((r) => {
          const meta = KIND_META[r.kind];
          return (
            <Card key={r.id} className="p-4">
              <div className="flex items-start gap-2">
                <div className={cn("flex h-8 w-8 items-center justify-center rounded-md", meta.tone)}>
                  <ShieldAlert className="h-4 w-4" />
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{meta.label}</span>
                    <span className="ml-auto text-[11px] text-muted-foreground">{Math.round(r.confidence * 100)}% conf.</span>
                  </div>
                  <div className="mt-1 text-base font-semibold">{r.subject_label}</div>
                  <div className="text-[11px] text-muted-foreground">{r.signal} · {formatDistanceToNow(new Date(r.created_at))} ago</div>
                </div>
              </div>
              <p className="mt-3 text-sm text-foreground">{r.rationale}</p>
              <div className="mt-3 flex items-center gap-2">
                <code className="rounded bg-muted px-1.5 py-0.5 text-[10px] text-muted-foreground">{meta.endpoint}</code>
                <div className="ml-auto flex gap-2">
                  <Button size="sm" variant="ghost" className="gap-1.5" onClick={() => handleDismiss(r.id)} disabled={working === r.id}>
                    <X className="h-3.5 w-3.5" /> Dismiss
                  </Button>
                  <Button size="sm" className="gap-1.5" onClick={() => handleApprove(r.id)} disabled={working === r.id}>
                    {working === r.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Check className="h-3.5 w-3.5" />} Approve
                  </Button>
                </div>
              </div>
            </Card>
          );
        })}
        {open.length === 0 && (
          <Card className="col-span-full p-8 text-center text-sm text-muted-foreground">No open recommendations.</Card>
        )}
      </div>

      {resolved.length > 0 && (
        <Card className="p-0">
          <div className="border-b px-4 py-2.5 text-sm font-medium">Resolved</div>
          <ul>
            {resolved.map((r) => (
              <li key={r.id} className="flex items-center gap-3 border-b px-4 py-2.5 text-xs last:border-b-0">
                <span className="capitalize">{r.kind.replace(/_/g, " ")}</span>
                <span className="text-muted-foreground">· {r.subject_label}</span>
                <span className="ml-auto"><Badge variant={r.status === "approved" ? "default" : "secondary"}>{r.status}</Badge></span>
                <span className="text-muted-foreground">{format(new Date(r.created_at), "yyyy-MM-dd")}</span>
              </li>
            ))}
          </ul>
        </Card>
      )}
    </div>
  );
}
