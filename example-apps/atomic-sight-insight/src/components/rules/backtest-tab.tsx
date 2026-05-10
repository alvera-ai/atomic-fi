import { useEffect, useMemo, useState } from "react";
import { format, formatDistanceToNow } from "date-fns";
import { CalendarIcon, Play, Rocket, AlertTriangle, CheckCircle2 } from "lucide-react";
import type { Rule } from "@/api/types";
import {
  runBacktest, recordBacktest, listBacktestHistory, promoteRule,
  type BacktestResult, type BacktestHistoryEntry,
} from "@/api/rules";
import { transactions, accountHolders } from "@/data/fixtures";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Calendar } from "@/components/ui/calendar";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Badge } from "@/components/ui/badge";
import { useAuth } from "@/contexts/auth-context";
import { usePermission } from "@/hooks/use-permission";
import { useAuditLogger } from "@/hooks/use-audit-logger";
import { toast } from "@/hooks/use-toast";
import { cn } from "@/lib/utils";
import { shortId } from "@/lib/money";

const HIT_RATE_MIN = 0.001; // 0.1%
const HIT_RATE_MAX = 0.05;  // 5%

export function BacktestTab({ rule, onPromoted }: { rule: Rule; onPromoted?: () => void }) {
  const { user } = useAuth();
  const canPromote = usePermission("rule.promote");
  const logAudit = useAuditLogger();

  const defaultEnd = useMemo(() => new Date(), []);
  const defaultStart = useMemo(() => new Date(Date.now() - 30 * 86_400_000), []);
  const [from, setFrom] = useState<Date | undefined>(defaultStart);
  const [to, setTo] = useState<Date | undefined>(defaultEnd);
  const [running, setRunning] = useState(false);
  const [result, setResult] = useState<BacktestResult | null>(null);
  const [history, setHistory] = useState<BacktestHistoryEntry[]>([]);
  const [historyTick, setHistoryTick] = useState(0);

  useEffect(() => {
    setHistory(listBacktestHistory(rule.id, 3));
  }, [rule.id, historyTick]);

  const datasetSize = rule.scope === "transaction" ? transactions.length : accountHolders.length;

  const run = async () => {
    setRunning(true);
    try {
      const r = await runBacktest(rule, {
        scope: rule.scope,
        fromDate: from ? format(from, "yyyy-MM-dd") : undefined,
        toDate: to ? format(to, "yyyy-MM-dd") : undefined,
      });
      setResult(r);
      recordBacktest({
        rule_id: rule.id,
        run_by: user.name,
        hit_rate: r.hitRate,
        hit_count: r.hitCount,
        total_evaluated: r.totalEvaluated,
        from_date: from ? format(from, "yyyy-MM-dd") : undefined,
        to_date: to ? format(to, "yyyy-MM-dd") : undefined,
      });
      setHistoryTick((n) => n + 1);
      logAudit({
        action_type: "rule.edited",
        resource_type: "rule",
        resource_id: rule.id,
        description: `Ran backtest on '${rule.name}' (${r.hitCount}/${r.totalEvaluated} hits)`,
        metadata: { hit_rate: r.hitRate, from_date: from?.toISOString(), to_date: to?.toISOString() },
      });
    } finally {
      setRunning(false);
    }
  };

  // Threshold sensitivity: simulate ±20% threshold change.
  // Approximation: hits with confidence ≥ adjustedThreshold pass.
  const sensitivity = useMemo(() => {
    if (!result) return null;
    const t = rule.threshold;
    const lower = Math.max(0, t * 0.8);
    const upper = Math.min(1, t * 1.2);
    // result.hits already filtered by t. We need confidence distribution to estimate.
    const confidences = result.hits.map((h) => h.confidence);
    const total = result.totalEvaluated || 1;
    const lowerCount = confidences.filter((c) => c >= lower).length;
    const upperCount = confidences.filter((c) => c >= upper).length;
    return {
      currentRate: result.hitRate,
      lowerRate: lowerCount / total,
      upperRate: upperCount / total,
    };
  }, [result, rule.threshold]);

  const inRange = result && result.hitRate >= HIT_RATE_MIN && result.hitRate <= HIT_RATE_MAX;
  const fpRate = result ? Math.min(0.95, Math.max(0.05, 1 - result.hitRate * 8)) : 0;

  const doPromote = async () => {
    await promoteRule(rule.id, user.name);
    logAudit({
      action_type: "rule.promoted",
      resource_type: "rule",
      resource_id: rule.id,
      description: `Promoted rule '${rule.name}' from Sandbox to Live (post-backtest)`,
      metadata: { from: "sandbox", to: "live", via: "backtest" },
    });
    toast({ title: "Promoted to live", description: `By ${user.name}` });
    onPromoted?.();
  };

  return (
    <div className="space-y-3">
      {/* Configuration */}
      <Card className="p-4">
        <div className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
          Configuration
        </div>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <DateField label="Start date" value={from} onChange={setFrom} />
          <DateField label="End date" value={to} onChange={setTo} />
          <div>
            <div className="text-[11px] font-medium">Scope</div>
            <div className="mt-1 flex h-9 items-center rounded-md border bg-muted/30 px-3 text-xs">
              <Badge variant="secondary" className="mr-2 capitalize">
                {rule.scope.replace(/_/g, " ")}
              </Badge>
              <span className="text-muted-foreground">{datasetSize} {rule.scope === "transaction" ? "transactions" : "holders"}</span>
            </div>
          </div>
        </div>
        <div className="mt-3 text-[11px] text-muted-foreground">
          Test against {rule.scope === "transaction" ? "transactions" : "account holders"} from{" "}
          <span className="font-medium text-foreground">{from ? format(from, "yyyy-MM-dd") : "—"}</span>
          {" "}to{" "}
          <span className="font-medium text-foreground">{to ? format(to, "yyyy-MM-dd") : "—"}</span>
        </div>
        <Button onClick={run} disabled={running} size="sm" className="mt-3 gap-1.5">
          <Play className="h-3.5 w-3.5" /> {running ? "Running…" : "Run backtest"}
        </Button>
      </Card>

      {/* Results */}
      {result && (
        <Card className="p-4">
          <div className="mb-3 flex items-center justify-between">
            <div className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
              Simulation report
            </div>
            <Badge
              variant="secondary"
              className={cn(
                "text-[10px]",
                inRange
                  ? "bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-300"
                  : "bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-300",
              )}
            >
              {inRange ? "Healthy hit rate" : "Outside target range"}
            </Badge>
          </div>

          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <Stat label="Total evaluated" value={String(result.totalEvaluated)} />
            <Stat label="Total flagged" value={String(result.hitCount)} />
            <Stat label="Hit rate" value={`${(result.hitRate * 100).toFixed(2)}%`} />
            <Stat label="Est. false positive" value={`${Math.round(fpRate * 100)}%`} />
          </div>

          {/* Hits table */}
          <div className="mt-4 overflow-hidden rounded-md border">
            <table className="w-full text-xs">
              <thead className="bg-muted/40 text-[10px] uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-3 py-2 text-left font-medium">ID</th>
                  <th className="px-3 py-2 text-left font-medium">{rule.scope === "transaction" ? "Amount" : "Name"}</th>
                  <th className="px-3 py-2 text-left font-medium">Reason</th>
                  <th className="px-3 py-2 text-right font-medium">Risk score</th>
                </tr>
              </thead>
              <tbody>
                {result.hits.length === 0 && (
                  <tr><td colSpan={4} className="px-3 py-4 text-center text-muted-foreground">No matches in this slice.</td></tr>
                )}
                {result.hits.slice(0, 25).map((h) => {
                  const subj = rule.scope === "transaction"
                    ? transactions.find((t) => t.id === h.subject_id)
                    : accountHolders.find((a) => a.id === h.subject_id);
                  const label = rule.scope === "transaction"
                    ? subj && "amount" in subj ? `${subj.currency} ${subj.amount.toLocaleString()}` : "—"
                    : subj && "display_name" in subj ? subj.display_name : "—";
                  const reason = h.matched_conditions.filter((c) => c.matched).slice(0, 2)
                    .map((c) => `${c.field} ${c.operator}`).join(", ") || rule.name;
                  return (
                    <tr key={h.id} className="border-t">
                      <td className="px-3 py-1.5 font-mono text-[10px]">{shortId(h.subject_id, 10)}</td>
                      <td className="px-3 py-1.5">{label}</td>
                      <td className="px-3 py-1.5 text-muted-foreground">{reason}</td>
                      <td className="px-3 py-1.5 text-right font-mono">{Math.round(h.confidence * 100)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>

          {/* Sensitivity */}
          {sensitivity && (
            <div className="mt-3 rounded-md border bg-muted/30 px-3 py-2 text-[11px]">
              If you adjust the threshold by ±20%, hit rate changes from{" "}
              <span className="font-mono font-semibold">{(sensitivity.upperRate * 100).toFixed(2)}%</span>
              {" "}(stricter) to{" "}
              <span className="font-mono font-semibold">{(sensitivity.lowerRate * 100).toFixed(2)}%</span>
              {" "}(looser). Current: {(sensitivity.currentRate * 100).toFixed(2)}%.
            </div>
          )}

          {/* Recommendation */}
          <div
            className={cn(
              "mt-3 flex items-start gap-2 rounded-md border px-3 py-2 text-xs",
              inRange
                ? "border-emerald-200 bg-emerald-50 text-emerald-900 dark:border-emerald-900 dark:bg-emerald-950/50 dark:text-emerald-200"
                : "border-amber-200 bg-amber-50 text-amber-900 dark:border-amber-900 dark:bg-amber-950/50 dark:text-amber-200",
            )}
          >
            {inRange ? <CheckCircle2 className="mt-0.5 h-4 w-4" /> : <AlertTriangle className="mt-0.5 h-4 w-4" />}
            <div>
              {inRange
                ? "This rule looks ready for Sandbox. Hit rate is within the 0.1%–5% target range."
                : `Review hit rate before promoting. Target range is 0.1%–5%; current is ${(result.hitRate * 100).toFixed(2)}%.`}
            </div>
          </div>

          {/* Promote */}
          {rule.status === "sandbox" && inRange && (
            <div className="mt-3">
              {canPromote ? (
                <Button size="sm" onClick={doPromote} className="gap-1.5">
                  <Rocket className="h-3.5 w-3.5" /> Promote to live
                </Button>
              ) : (
                <div className="text-[11px] text-muted-foreground">
                  Promotion requires the compliance_officer role.
                </div>
              )}
            </div>
          )}
        </Card>
      )}

      {/* History */}
      <Card className="p-4">
        <div className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
          Backtest history
        </div>
        {history.length === 0 ? (
          <div className="text-xs text-muted-foreground">No backtests run yet.</div>
        ) : (
          <ul className="divide-y">
            {history.map((h) => (
              <li key={h.id} className="flex items-center gap-3 py-2 text-xs">
                <div className="flex-1">
                  <div className="font-medium">{h.run_by}</div>
                  <div className="text-[11px] text-muted-foreground">
                    {formatDistanceToNow(new Date(h.run_at), { addSuffix: true })} · {h.hit_count}/{h.total_evaluated} hits
                  </div>
                </div>
                <Badge variant="secondary" className="font-mono text-[10px]">
                  {(h.hit_rate * 100).toFixed(2)}%
                </Badge>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border bg-card p-3">
      <div className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</div>
      <div className="mt-0.5 text-base font-semibold">{value}</div>
    </div>
  );
}

function DateField({ label, value, onChange }: { label: string; value?: Date; onChange: (d?: Date) => void }) {
  return (
    <div>
      <div className="text-[11px] font-medium">{label}</div>
      <Popover>
        <PopoverTrigger asChild>
          <Button variant="outline" className={cn("mt-1 h-9 w-full justify-start text-left font-normal", !value && "text-muted-foreground")}>
            <CalendarIcon className="mr-1.5 h-3.5 w-3.5" />
            {value ? format(value, "yyyy-MM-dd") : "Pick a date"}
          </Button>
        </PopoverTrigger>
        <PopoverContent className="w-auto p-0" align="start">
          <Calendar mode="single" selected={value} onSelect={onChange} initialFocus className={cn("p-3 pointer-events-auto")} />
        </PopoverContent>
      </Popover>
    </div>
  );
}
