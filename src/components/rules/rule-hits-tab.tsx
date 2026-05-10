import { Check, X } from "lucide-react";
import type { RuleHit } from "@/api/types";
import { StatusPill } from "@/components/status-pill";

const fmtVal = (v: unknown): string => {
  if (v === null || v === undefined) return "—";
  if (Array.isArray(v)) return `[${v.join(", ")}]`;
  return String(v);
};

export function RuleHitsTab({ hits }: { hits: RuleHit[] }) {
  if (hits.length === 0) {
    return <div className="text-sm text-muted-foreground">No rule breaches.</div>;
  }
  return (
    <div className="space-y-3">
      {hits.sort((a, b) => b.confidence - a.confidence).map((h) => (
        <div key={h.id} className="rounded-md border bg-card p-3">
          <div className="mb-2 flex items-center gap-2">
            <div className="font-medium text-sm">{h.rule_name}</div>
            <StatusPill value={h.severity} />
            <StatusPill value={h.action} />
            <span className="ml-auto font-mono text-xs">{Math.round(h.confidence * 100)}%</span>
          </div>
          <div className="rounded border bg-muted/30">
            {h.matched_conditions.map((m, i) => (
              <div key={i} className="flex items-center gap-2 border-b px-2 py-1.5 text-[11px] last:border-b-0">
                {m.matched
                  ? <Check className="h-3.5 w-3.5 text-success" />
                  : <X className="h-3.5 w-3.5 text-muted-foreground" />}
                <span className="font-mono">{m.field}</span>
                <span className="text-muted-foreground">{m.operator}</span>
                <span className="font-mono">{fmtVal(m.value)}</span>
                <span className="ml-auto text-muted-foreground">
                  actual: <span className="font-mono">{fmtVal(m.actual)}</span> · w{m.weight}
                </span>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}
