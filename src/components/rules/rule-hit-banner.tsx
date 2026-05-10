import { AlertTriangle, ShieldAlert } from "lucide-react";
import type { RuleHit } from "@/api/types";
import { cn } from "@/lib/utils";

export function RuleHitBanner({
  hits, onView, className,
}: {
  hits: RuleHit[];
  onView?: () => void;
  className?: string;
}) {
  // Show banner when any hit is high/critical OR confidence ≥ 0.8
  const high = hits.filter((h) => h.severity === "high" || h.severity === "critical" || h.confidence >= 0.8);
  if (high.length === 0) return null;
  const top = high.sort((a, b) => b.confidence - a.confidence)[0];
  const isCrit = top.severity === "critical";
  return (
    <div
      className={cn(
        "flex items-center gap-2 rounded-md border px-3 py-2 text-xs",
        isCrit
          ? "border-destructive/40 bg-destructive/10 text-destructive"
          : "border-warning/40 bg-warning/10 text-warning-foreground",
        className,
      )}
    >
      {isCrit ? <ShieldAlert className="h-4 w-4 shrink-0" /> : <AlertTriangle className="h-4 w-4 shrink-0" />}
      <div className="min-w-0 flex-1">
        <div className="font-semibold">
          {high.length} rule {high.length === 1 ? "breach" : "breaches"} · top: {top.rule_name}
        </div>
        <div className="text-[11px] opacity-80">
          {top.severity} · {top.action} · confidence {Math.round(top.confidence * 100)}%
        </div>
      </div>
      {onView && (
        <button onClick={onView} className="rounded border border-current/30 px-2 py-1 text-[11px] font-medium hover:bg-current/10">
          View
        </button>
      )}
    </div>
  );
}
