import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { formatDistanceToNow } from "date-fns";
import {
  AlertTriangle, ArrowRight, Briefcase, ClipboardList, Scale, TrendingDown, TrendingUp,
} from "lucide-react";
import { Card } from "@/components/ui/card";
import { listCases, type Case, type CasePriority } from "@/api/cases";
import { listRules } from "@/api/rules";
import { listAccountHolders } from "@/api";
import type { Rule } from "@/api/types";
import type { AccountHolderResponse } from "@/api/types";
import { cn } from "@/lib/utils";

interface ActivityEntry {
  id: string;
  actor: string;
  text: string;
  at: string; // iso
}

const RULE_HITS: Record<string, number> = {
  "Transfer to blocked counterparty": 47,
  "High-risk holder over 1M USD": 12,
  "Sanctioned creditor jurisdiction": 8,
  "Screening match present": 23,
  "Holder KYC not approved": 64,
  "EDD required for high-risk holder": 19,
  "Velocity: large transfers in 24h": 31,
  "Card payment to suspended counterparty": 5,
};

const minsAgo = (n: number) => new Date(Date.now() - n * 60_000).toISOString();
const hoursAgo = (n: number) => new Date(Date.now() - n * 3_600_000).toISOString();

const ACTIVITY: ActivityEntry[] = [
  { id: "a1", actor: "Ana Martins", text: "closed case CASE-007 — Duplicate payment instruction", at: minsAgo(18) },
  { id: "a2", actor: "James Osei", text: "promoted rule 'Sanctioned creditor jurisdiction' to Live", at: minsAgo(52) },
  { id: "a3", actor: "Priya Shah", text: "reassigned case CASE-002 to Marcus Chen", at: hoursAgo(2) },
  { id: "a4", actor: "Alex Ortega", text: "escalated case CASE-005 to MLRO sign-off", at: hoursAgo(3) },
  { id: "a5", actor: "Sofía Reyes", text: "approved KYC for Helios Energy GmbH", at: hoursAgo(5) },
  { id: "a6", actor: "Marcus Chen", text: "sent outreach to ops@acme.io requesting source of funds", at: hoursAgo(7) },
  { id: "a7", actor: "Yuki Tanaka", text: "archived rule 'Legacy: any transfer over 100k'", at: hoursAgo(11) },
  { id: "a8", actor: "Liam O'Connor", text: "flagged 4 transactions on ShadowBank Holdings", at: hoursAgo(14) },
  { id: "a9", actor: "Ana Martins", text: "approved 2 KYC requirements for Nordic Freight AB", at: hoursAgo(20) },
  { id: "a10", actor: "James Osei", text: "ran backtest on 'Velocity: large transfers in 24h'", at: hoursAgo(26) },
];

const PRIORITY_ORDER: CasePriority[] = ["critical", "high", "medium", "low"];
const PRIORITY_STYLES: Record<CasePriority, string> = {
  critical: "bg-destructive/10 text-destructive border-destructive/30",
  high: "bg-warning/10 text-warning-foreground border-warning/30",
  medium: "bg-muted text-foreground border-border",
  low: "bg-muted/40 text-muted-foreground border-border",
};

function initials(name: string) {
  return name.split(" ").map((p) => p[0]).slice(0, 2).join("").toUpperCase();
}

function StatCard({
  label, value, icon: Icon, hint, hintTone = "neutral", danger = false,
}: {
  label: string;
  value: number | string;
  icon: React.ElementType;
  hint?: string;
  hintTone?: "up" | "down" | "neutral";
  danger?: boolean;
}) {
  return (
    <Card className={cn("p-4", danger && "border-destructive/40 bg-destructive/5")}>
      <div className="flex items-center gap-2">
        <div className={cn(
          "grid h-8 w-8 place-items-center rounded-md",
          danger ? "bg-destructive/10 text-destructive" : "bg-muted text-foreground",
        )}>
          <Icon className="h-4 w-4" />
        </div>
        <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</div>
      </div>
      <div className={cn("mt-3 text-3xl font-semibold tabular-nums", danger && "text-destructive")}>
        {value}
      </div>
      {hint && (
        <div className={cn(
          "mt-1 flex items-center gap-1 text-[11px]",
          hintTone === "up" && "text-destructive",
          hintTone === "down" && "text-success",
          hintTone === "neutral" && "text-muted-foreground",
        )}>
          {hintTone === "up" && <TrendingUp className="h-3 w-3" />}
          {hintTone === "down" && <TrendingDown className="h-3 w-3" />}
          <span>{hint}</span>
        </div>
      )}
    </Card>
  );
}

export default function DashboardPage() {
  const [cases, setCases] = useState<Case[]>([]);
  const [rules, setRules] = useState<Rule[]>([]);
  const [holders, setHolders] = useState<AccountHolderResponse[]>([]);

  useEffect(() => {
    listCases().then(setCases);
    listRules().then(setRules);
    listAccountHolders().then(setHolders);
  }, []);

  const openCases = useMemo(() => cases.filter((c) => c.status !== "closed"), [cases]);
  const overdueCases = useMemo(
    () => openCases.filter((c) => new Date(c.due_date).getTime() < Date.now()),
    [openCases],
  );
  const pendingOnboarding = useMemo(
    () => holders.filter((h) => h.kyc_status === "in_progress" || h.kyc_status === "on_hold").length,
    [holders],
  );
  const liveRules = useMemo(() => rules.filter((r) => r.status === "live"), [rules]);

  const grouped = useMemo(() => {
    const out: Record<CasePriority, Case[]> = { critical: [], high: [], medium: [], low: [] };
    openCases.forEach((c) => out[c.priority]?.push(c));
    return out;
  }, [openCases]);

  return (
    <div className="space-y-4 p-4">
      <div>
        <h1 className="text-xl font-semibold tracking-tight">Compliance dashboard</h1>
        <p className="text-xs text-muted-foreground">Program health and queue at a glance.</p>
      </div>

      {/* SECTION 1 — Program Health */}
      <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Open cases"
          value={openCases.length}
          icon={Briefcase}
          hint="↑ 3 from last week"
          hintTone="up"
        />
        <StatCard
          label="Pending onboarding"
          value={pendingOnboarding}
          icon={ClipboardList}
          hint="awaiting review"
        />
        <StatCard
          label="Rules active"
          value={liveRules.length}
          icon={Scale}
          hint="in production"
        />
        <StatCard
          label="Overdue cases"
          value={overdueCases.length}
          icon={AlertTriangle}
          hint={overdueCases.length > 0 ? "past due date" : "all on track"}
          danger={overdueCases.length > 0}
        />
      </div>

      {/* SECTION 2 + 3 */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        {/* Case queue overview */}
        <Card className="overflow-hidden">
          <div className="flex items-center justify-between border-b px-4 py-3">
            <div>
              <div className="text-sm font-semibold">Case queue overview</div>
              <div className="text-[11px] text-muted-foreground">Open cases grouped by priority</div>
            </div>
            <Link
              to="/queue"
              className="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline"
            >
              View all <ArrowRight className="h-3 w-3" />
            </Link>
          </div>
          <div className="divide-y">
            {PRIORITY_ORDER.map((p) => {
              const list = grouped[p];
              return (
                <div key={p} className="px-4 py-3">
                  <div className="flex items-center gap-2">
                    <span className={cn(
                      "rounded-md border px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide",
                      PRIORITY_STYLES[p],
                    )}>
                      {p}
                    </span>
                    <span className="text-sm font-semibold tabular-nums">{list.length}</span>
                    <span className="text-[11px] text-muted-foreground">open</span>
                  </div>
                  {p === "critical" && list.length > 0 && (
                    <ul className="mt-2 space-y-1">
                      {list.slice(0, 3).map((c) => (
                        <li key={c.id} className="flex items-center gap-2 text-xs">
                          <Link to="/queue" className="truncate font-medium hover:underline">
                            {c.title}
                          </Link>
                          <span className="ml-auto shrink-0 text-[11px] text-muted-foreground">
                            {c.assigned_to}
                          </span>
                        </li>
                      ))}
                    </ul>
                  )}
                </div>
              );
            })}
          </div>
        </Card>

        {/* Rule performance */}
        <Card className="overflow-hidden">
          <div className="border-b px-4 py-3">
            <div className="text-sm font-semibold">Rule performance</div>
            <div className="text-[11px] text-muted-foreground">Live rules and recent hit volume</div>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead className="bg-muted/40 text-[10px] uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-4 py-2 text-left font-medium">Rule name</th>
                  <th className="px-4 py-2 text-right font-medium">Hits (30d)</th>
                  <th className="px-4 py-2 text-left font-medium">Action</th>
                </tr>
              </thead>
              <tbody>
                {liveRules.slice(0, 6).map((r) => (
                  <tr key={r.id} className="border-t">
                    <td className="px-4 py-2 font-medium">{r.name}</td>
                    <td className="px-4 py-2 text-right tabular-nums">
                      {RULE_HITS[r.name] ?? Math.floor(5 + Math.random() * 40)}
                    </td>
                    <td className="px-4 py-2 capitalize text-muted-foreground">
                      {(typeof r.action === "string" ? r.action : (r.action as { kind?: string })?.kind ?? "review").replace(/_/g, " ")}
                    </td>
                  </tr>
                ))}
                {liveRules.length === 0 && (
                  <tr><td colSpan={3} className="px-4 py-6 text-center text-muted-foreground">No live rules.</td></tr>
                )}
              </tbody>
            </table>
          </div>
          <div className="border-t bg-muted/30 px-4 py-2 text-[11px] text-muted-foreground">
            Full backtest analytics coming soon
          </div>
        </Card>
      </div>

      {/* SECTION 4 — Recent activity */}
      <Card className="overflow-hidden">
        <div className="border-b px-4 py-3">
          <div className="text-sm font-semibold">Recent activity</div>
          <div className="text-[11px] text-muted-foreground">Last 10 actions across the team</div>
        </div>
        <ul className="divide-y">
          {ACTIVITY.map((a) => (
            <li key={a.id} className="flex items-center gap-3 px-4 py-2.5">
              <div className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-primary/10 text-[11px] font-semibold text-primary">
                {initials(a.actor)}
              </div>
              <div className="min-w-0 flex-1 text-xs">
                <span className="font-medium">{a.actor}</span>{" "}
                <span className="text-muted-foreground">{a.text}</span>
              </div>
              <div className="shrink-0 text-[11px] text-muted-foreground">
                {formatDistanceToNow(new Date(a.at), { addSuffix: true })}
              </div>
            </li>
          ))}
        </ul>
      </Card>
    </div>
  );
}
