import {
  accountHolders, beneficialOwners, complianceScreenings, counterparties,
  documents, kycRequirements, transactions,
} from "@/data/fixtures";
import type { Rule, RuleHit, RuleScope } from "@/api/types";
import {
  buildHolderFact, buildTransactionFact, evaluateRules, type FactSources,
} from "@/lib/rules/engine";
import { seedRules } from "@/lib/rules/fixtures";
import { conditionTreeToJdm } from "@/lib/rules/jdm";

// Auto-migrate any seed/legacy rule lacking a JDM graph.
const ensureJdm = (r: Rule): Rule =>
  r.content ? r : { ...r, content: conditionTreeToJdm(r.when, r.name) };

let ruleStore: Rule[] = seedRules.map(ensureJdm);
// hits keyed by `${scope}:${subjectId}` → live hits only
let liveHits: Record<string, RuleHit[]> = {};
const subscribers = new Set<() => void>();

export const factSources = (): FactSources => ({
  accountHolders, counterparties, beneficialOwners,
  kycRequirements, documents, screenings: complianceScreenings,
});

const key = (scope: RuleScope, subjectId: string) => `${scope}:${subjectId}`;

export function recomputeAllLiveHits() {
  const live = ruleStore.filter((r) => r.status === "live");
  const txRules = live.filter((r) => r.scope === "transaction");
  const ahRules = live.filter((r) => r.scope === "account_holder");
  const next: Record<string, RuleHit[]> = {};
  const src = factSources();
  for (const tx of transactions) {
    const fact = buildTransactionFact(tx, src);
    const hits = evaluateRules(txRules, fact, tx.id, "live");
    if (hits.length) next[key("transaction", tx.id)] = hits;
  }
  for (const h of accountHolders) {
    const fact = buildHolderFact(h, src);
    const hits = evaluateRules(ahRules, fact, h.id, "live");
    if (hits.length) next[key("account_holder", h.id)] = hits;
  }
  liveHits = next;
  subscribers.forEach((cb) => cb());
}

recomputeAllLiveHits();

export const getRules = () => [...ruleStore];
export const getRule = (id: string) => ruleStore.find((r) => r.id === id);
export const upsertRule = (rule: Rule) => {
  const next = ensureJdm(rule);
  const exists = ruleStore.some((r) => r.id === next.id);
  ruleStore = exists ? ruleStore.map((r) => (r.id === next.id ? next : r)) : [next, ...ruleStore];
  recomputeAllLiveHits();
};
export const removeRule = (id: string) => {
  ruleStore = ruleStore.filter((r) => r.id !== id);
  recomputeAllLiveHits();
};

export const getLiveHits = (scope: RuleScope, subjectId: string): RuleHit[] =>
  liveHits[key(scope, subjectId)] ?? [];

export const getAllLiveHits = (): RuleHit[] => Object.values(liveHits).flat();

export const subscribe = (cb: () => void): (() => void) => {
  subscribers.add(cb);
  return () => { subscribers.delete(cb); };
};
