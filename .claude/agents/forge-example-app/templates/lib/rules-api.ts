// CRUD against the Phoenix REST surface for JDM rule files.
//
// The thin shim lives at lib/atomic_fi_api/controllers/rule_controller.ex —
// rules are read/written as raw JDM JSON keyed by (rule_type, name).
// The agent's authored rule lives at priv/zenrule/<rule_type>/<name>.json
// and is hot-loaded by ZenRule on every change.

import { getStoredBearer } from "./session";

const API_BASE = "";

function bearer(): string {
  const t = getStoredBearer();
  if (!t) throw new Error("Not signed in. LoginGate must run first.");
  return t;
}

export type RuleType = "onboarding" | "transaction-screening";

// JDM JSON is unstructured for our purposes — pass it through as a generic
// object. The DecisionGraph component takes care of validating the shape.
export type JdmDocument = Record<string, unknown>;

export async function listRules(ruleType: RuleType): Promise<string[]> {
  const res = await fetch(`${API_BASE}/api/rules/${ruleType}`, {
    headers: { authorization: `Bearer ${bearer()}` },
  });
  if (!res.ok) throw new Error(`listRules: ${res.status} ${await res.text()}`);
  const body = (await res.json()) as { rules: string[] };
  return body.rules;
}

export async function getRule(ruleType: RuleType, name: string): Promise<JdmDocument> {
  const res = await fetch(`${API_BASE}/api/rules/${ruleType}/${encodeURIComponent(name)}`, {
    headers: { authorization: `Bearer ${bearer()}` },
  });
  if (!res.ok) throw new Error(`getRule(${name}): ${res.status} ${await res.text()}`);
  return (await res.json()) as JdmDocument;
}

export async function upsertRule(ruleType: RuleType, name: string, jdm: JdmDocument): Promise<void> {
  const res = await fetch(`${API_BASE}/api/rules/${ruleType}/${encodeURIComponent(name)}`, {
    method: "PUT",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${bearer()}`,
    },
    body: JSON.stringify(jdm),
  });
  if (!res.ok) throw new Error(`upsertRule(${name}): ${res.status} ${await res.text()}`);
}
