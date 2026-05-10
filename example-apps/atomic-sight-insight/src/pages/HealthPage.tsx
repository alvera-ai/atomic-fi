import { useEffect, useMemo, useState } from "react";
import { Activity, Check, Database, GaugeCircle, RefreshCcw } from "lucide-react";
import { Area, AreaChart, ResponsiveContainer, XAxis, YAxis } from "recharts";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { getApiInfo } from "@/api";
import type { ApiInfoResponse } from "@/api/types";

function uptimeStr(seconds: number) {
  const d = Math.floor(seconds / 86_400);
  const h = Math.floor((seconds % 86_400) / 3_600);
  const m = Math.floor((seconds % 3_600) / 60);
  return `${d}d ${h}h ${m}m`;
}

// Mock series — render only.
function makeSeries(seed: number, n = 30, base = 50, jitter = 25) {
  const out: { t: number; v: number }[] = [];
  let x = seed;
  for (let i = 0; i < n; i++) {
    x = (x * 9301 + 49297) % 233280;
    const v = Math.max(1, base + (x / 233280 - 0.5) * jitter * 2);
    out.push({ t: i, v: Math.round(v) });
  }
  return out;
}

export default function HealthPage() {
  const [info, setInfo] = useState<ApiInfoResponse | null>(null);
  const [loading, setLoading] = useState(false);

  const load = async () => {
    setLoading(true);
    try { setInfo(await getApiInfo()); } finally { setLoading(false); }
  };
  useEffect(() => { load(); }, []);

  const rps = useMemo(() => makeSeries(42, 30, 220, 80), []);
  const p95 = useMemo(() => makeSeries(7, 30, 180, 90), []);
  const queue = useMemo(() => makeSeries(13, 30, 12, 14), []);

  return (
    <div className="flex h-full flex-col gap-4 overflow-y-auto p-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Health</h1>
          <p className="text-xs text-muted-foreground">Real GET /api/info; the rest is preview from in-memory mock until the metrics endpoint ships.</p>
        </div>
        <Button size="sm" variant="outline" className="gap-1.5" onClick={load} disabled={loading}>
          <RefreshCcw className={loading ? "h-3.5 w-3.5 animate-spin" : "h-3.5 w-3.5"} /> Refresh
        </Button>
      </div>

      <Card className="p-4">
        <div className="mb-2 flex items-center gap-2">
          <Database className="h-4 w-4 text-primary" />
          <h2 className="text-sm font-semibold">API info</h2>
          <code className="ml-auto rounded bg-muted px-1.5 py-0.5 text-[10px] text-muted-foreground">GET /api/info</code>
        </div>
        {info ? (
          <div className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-4">
            <Field label="Version">{info.version}</Field>
            <Field label="Build">{info.build}</Field>
            <Field label="DB status">
              <span className="inline-flex items-center gap-1.5">
                <span className={`h-2 w-2 rounded-full ${info.database_status === "ok" ? "bg-success" : info.database_status === "degraded" ? "bg-warning" : "bg-destructive"}`} />
                <span className="capitalize">{info.database_status}</span>
              </span>
            </Field>
            <Field label="Uptime">{uptimeStr(info.uptime_seconds)}</Field>
            <Field label="Channel">{info.release_channel}</Field>
          </div>
        ) : <div className="text-xs text-muted-foreground">Loading…</div>}
      </Card>

      <div className="grid grid-cols-1 gap-3 lg:grid-cols-3">
        <MetricCard icon={Activity} title="Requests / sec" value={String(rps.at(-1)?.v ?? 0)} series={rps} color="hsl(var(--primary))" />
        <MetricCard icon={GaugeCircle} title="p95 latency (ms)" value={String(p95.at(-1)?.v ?? 0)} series={p95} color="hsl(var(--info))" />
        <MetricCard icon={Check} title="Queue depth" value={String(queue.at(-1)?.v ?? 0)} series={queue} color="hsl(var(--warning))" />
      </div>

      <p className="text-[11px] text-muted-foreground">
        <Badge variant="secondary" className="mr-1.5">preview</Badge>
        rps / p95 / queue depth are rendered from in-memory mock — the metrics endpoint isn't in the AtomicFi spec yet.
      </p>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <div className="text-[11px] uppercase tracking-wide text-muted-foreground">{label}</div>
      <div className="font-medium">{children}</div>
    </div>
  );
}

function MetricCard({
  icon: Icon, title, value, series, color,
}: {
  icon: typeof Activity; title: string; value: string; series: { t: number; v: number }[]; color: string;
}) {
  return (
    <Card className="p-4">
      <div className="flex items-center gap-2">
        <Icon className="h-4 w-4 text-muted-foreground" />
        <div className="text-xs font-medium text-muted-foreground">{title}</div>
        <Badge variant="secondary" className="ml-auto text-[10px]">preview</Badge>
      </div>
      <div className="mt-1 text-2xl font-semibold tabular-nums">{value}</div>
      <div className="mt-2 h-20">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={series} margin={{ top: 4, right: 0, bottom: 0, left: 0 }}>
            <defs>
              <linearGradient id={`g-${title}`} x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor={color} stopOpacity={0.4} />
                <stop offset="100%" stopColor={color} stopOpacity={0} />
              </linearGradient>
            </defs>
            <XAxis dataKey="t" hide />
            <YAxis hide />
            <Area type="monotone" dataKey="v" stroke={color} strokeWidth={1.5} fill={`url(#g-${title})`} />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </Card>
  );
}
