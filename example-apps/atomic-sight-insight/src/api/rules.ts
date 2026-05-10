import { transactions, accountHolders } from "@/data/fixtures";
import type { Rule, RuleHit, TransactionResponse, AccountHolderResponse } from "@/api/types";
import { buildHolderFact, buildTransactionFact, evaluateRules } from "@/lib/rules/engine";
import { factSources, getRules, upsertRule, removeRule, getLiveHits, getAllLiveHits, subscribe } from "@/lib/rules/store";

const delay = <T,>(v: T, ms = 200) => new Promise<T>((r) => setTimeout(() => r(v), ms));

export const listRules = (): Promise<Rule[]> => delay(getRules());
export const getRuleById = (id: string): Promise<Rule | undefined> => delay(getRules().find((r) => r.id === id));
export const saveRule = (rule: Rule): Promise<Rule> => {
  const next = { ...rule, updated_at: new Date().toISOString(), version: rule.version + (getRules().some((r) => r.id === rule.id) ? 1 : 0) };
  upsertRule(next);
  return delay(next, 250);
};
export const createRule = (rule: Omit<Rule, "id" | "created_at" | "updated_at" | "version">): Promise<Rule> => {
  const created: Rule = {
    ...rule, id: crypto.randomUUID(),
    created_at: new Date().toISOString(), updated_at: new Date().toISOString(), version: 1,
  };
  upsertRule(created);
  return delay(created, 250);
};
export const promoteRule = async (id: string, by?: string): Promise<Rule> => {
  const r = getRules().find((x) => x.id === id); if (!r) throw new Error("not found");
  return saveRule({
    ...r,
    status: "live",
    last_promoted_by: by ?? r.last_promoted_by ?? "unknown",
    last_promoted_at: new Date().toISOString(),
  });
};
export const archiveRule = async (id: string): Promise<Rule> => {
  const r = getRules().find((x) => x.id === id); if (!r) throw new Error("not found");
  return saveRule({ ...r, status: "archived" });
};
export const restoreRule = async (id: string): Promise<Rule> => {
  const r = getRules().find((x) => x.id === id); if (!r) throw new Error("not found");
  return saveRule({ ...r, status: "sandbox" });
};
export const deleteRule = (id: string): Promise<{ ok: true }> => { removeRule(id); return delay({ ok: true } as const, 150); };

export interface BacktestSlice {
  scope: "transaction" | "account_holder";
  fromDate?: string; // YYYY-MM-DD
  toDate?: string;
  statuses?: string[];
  sampleSize?: number;
}

export interface BacktestResult {
  ruleId: string;
  totalEvaluated: number;
  hitCount: number;
  hitRate: number;
  hits: RuleHit[];
  confidenceBuckets: { range: string; count: number }[];
  liveOverlap: number; // # of subjects where current live rules also fire
}

export const runBacktest = async (rule: Rule, slice: BacktestSlice): Promise<BacktestResult> => {
  const src = factSources();
  let subjects: Array<{ id: string; date: string; status?: string }> = [];
  if (rule.scope === "transaction") {
    subjects = transactions.map((t) => ({ id: t.id, date: t.inserted_at.slice(0, 10), status: t.status ?? undefined }));
  } else {
    subjects = accountHolders.map((h) => ({ id: h.id, date: h.inserted_at.slice(0, 10), status: h.kyc_status }));
  }
  if (slice.fromDate) subjects = subjects.filter((s) => s.date >= slice.fromDate!);
  if (slice.toDate) subjects = subjects.filter((s) => s.date <= slice.toDate!);
  if (slice.statuses && slice.statuses.length) subjects = subjects.filter((s) => s.status && slice.statuses!.includes(s.status));
  if (slice.sampleSize && slice.sampleSize < subjects.length) subjects = subjects.slice(0, slice.sampleSize);

  const hits: RuleHit[] = [];
  for (const s of subjects) {
    const fact = rule.scope === "transaction"
      ? buildTransactionFact(transactions.find((t) => t.id === s.id)!, src)
      : buildHolderFact(accountHolders.find((h) => h.id === s.id)!, src);
    const h = evaluateRules([rule], fact, s.id, "sandbox");
    hits.push(...h);
  }
  const buckets = [
    { range: "0.50–0.69", count: hits.filter((h) => h.confidence < 0.7).length },
    { range: "0.70–0.84", count: hits.filter((h) => h.confidence >= 0.7 && h.confidence < 0.85).length },
    { range: "0.85–1.00", count: hits.filter((h) => h.confidence >= 0.85).length },
  ];
  const liveSubjectIds = new Set(getAllLiveHits().filter((h) => h.scope === rule.scope).map((h) => h.subject_id));
  const liveOverlap = hits.filter((h) => liveSubjectIds.has(h.subject_id)).length;
  return delay({
    ruleId: rule.id,
    totalEvaluated: subjects.length,
    hitCount: hits.length,
    hitRate: subjects.length ? hits.length / subjects.length : 0,
    hits,
    confidenceBuckets: buckets,
    liveOverlap,
  }, 400);
};

export { getLiveHits, getAllLiveHits, subscribe };

// ───── Backtest history (in-memory)
export interface BacktestHistoryEntry {
  id: string;
  rule_id: string;
  run_by: string;
  run_at: string;
  hit_rate: number;
  hit_count: number;
  total_evaluated: number;
  from_date?: string;
  to_date?: string;
}

const backtestHistory: BacktestHistoryEntry[] = [];

export const recordBacktest = (entry: Omit<BacktestHistoryEntry, "id" | "run_at">): BacktestHistoryEntry => {
  const created: BacktestHistoryEntry = {
    ...entry,
    id: crypto.randomUUID(),
    run_at: new Date().toISOString(),
  };
  backtestHistory.unshift(created);
  return created;
};

export const listBacktestHistory = (ruleId: string, limit = 3): BacktestHistoryEntry[] =>
  backtestHistory.filter((e) => e.rule_id === ruleId).slice(0, limit);

