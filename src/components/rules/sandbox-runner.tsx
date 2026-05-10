import { useState } from "react";
import { Play } from "lucide-react";
import type { Rule, RuleHit } from "@/api/types";
import { runBacktest, type BacktestResult, type BacktestSlice } from "@/api/rules";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { StatusPill } from "@/components/status-pill";

export function SandboxRunner({ rule }: { rule: Rule }) {
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [sample, setSample] = useState<number | "">("");
  const [running, setRunning] = useState(false);
  const [result, setResult] = useState<BacktestResult | null>(null);

  const run = async () => {
    setRunning(true);
    const slice: BacktestSlice = {
      scope: rule.scope,
      fromDate: from || undefined,
      toDate: to || undefined,
      sampleSize: sample === "" ? undefined : Number(sample),
    };
    const r = await runBacktest(rule, slice);
    setResult(r);
    setRunning(false);
  };

  return (
    <div className="space-y-3">
      <div className="rounded-md border bg-card p-3">
        <div className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">Slice</div>
        <div className="grid grid-cols-3 gap-2">
          <div>
            <Label className="text-[11px]">From</Label>
            <Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="h-8" />
          </div>
          <div>
            <Label className="text-[11px]">To</Label>
            <Input type="date" value={to} onChange={(e) => setTo(e.target.value)} className="h-8" />
          </div>
          <div>
            <Label className="text-[11px]">Sample size</Label>
            <Input type="number" value={sample} onChange={(e) => setSample(e.target.value === "" ? "" : Number(e.target.value))} placeholder="all" className="h-8" />
          </div>
        </div>
        <Button onClick={run} disabled={running} size="sm" className="mt-3 gap-1.5">
          <Play className="h-3.5 w-3.5" /> {running ? "Running…" : "Run backtest"}
        </Button>
      </div>

      {result && (
        <>
          <div className="grid grid-cols-3 gap-2">
            <Stat label="Evaluated" value={String(result.totalEvaluated)} />
            <Stat label="Hits" value={String(result.hitCount)} />
            <Stat label="Hit rate" value={`${Math.round(result.hitRate * 100)}%`} />
          </div>
          <div className="rounded-md border bg-card p-3">
            <div className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">Confidence distribution</div>
            <div className="space-y-1">
              {result.confidenceBuckets.map((b) => (
                <div key={b.range} className="flex items-center gap-2 text-xs">
                  <div className="w-20 font-mono text-[11px] text-muted-foreground">{b.range}</div>
                  <div className="h-2 flex-1 rounded bg-muted">
                    <div className="h-full rounded bg-primary" style={{ width: `${result.hitCount ? (b.count / result.hitCount) * 100 : 0}%` }} />
                  </div>
                  <div className="w-8 text-right font-mono text-[11px]">{b.count}</div>
                </div>
              ))}
            </div>
            <div className="mt-2 text-[11px] text-muted-foreground">
              {result.liveOverlap} of {result.hitCount} subjects are also flagged by current live rules.
            </div>
          </div>
          <HitsList hits={result.hits} />
        </>
      )}
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border bg-card p-3">
      <div className="text-[11px] uppercase tracking-wide text-muted-foreground">{label}</div>
      <div className="mt-0.5 text-lg font-semibold">{value}</div>
    </div>
  );
}

function HitsList({ hits }: { hits: RuleHit[] }) {
  if (hits.length === 0) return <div className="text-xs text-muted-foreground">No hits in this slice.</div>;
  return (
    <div className="rounded-md border bg-card">
      <div className="border-b px-3 py-2 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">Matched subjects</div>
      <ul className="max-h-[280px] overflow-y-auto">
        {hits.slice(0, 100).map((h) => (
          <li key={h.id} className="flex items-center gap-2 border-b px-3 py-1.5 text-[11px] last:border-b-0">
            <span className="font-mono">{h.subject_id.slice(0, 8)}…</span>
            <StatusPill value={h.severity} />
            <span className="ml-auto font-mono">{Math.round(h.confidence * 100)}%</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
