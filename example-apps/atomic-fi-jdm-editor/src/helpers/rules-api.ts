import type { DecisionContent } from './graph';
import { atomicFiClient } from './clients';

export type RuleType = 'onboarding' | 'transaction-screening';

export const RULE_TYPES: RuleType[] = ['onboarding', 'transaction-screening'];

export const RULE_TYPE_LABELS: Record<RuleType, string> = {
  onboarding: 'Onboarding',
  'transaction-screening': 'Transaction screening',
};

// JDM-on-disk shape. The editor stores `{ contentType, nodes, edges }`;
// the backend stores raw bytes and returns whatever was last written.
export type RuleFile = DecisionContent & {
  contentType?: string;
};

export async function listRules(ruleType: RuleType): Promise<string[]> {
  const { data } = await atomicFiClient.get<{ rules: string[] }>(`/api/rules/${ruleType}`);
  return data.rules ?? [];
}

export async function getRule(ruleType: RuleType, name: string): Promise<RuleFile> {
  const { data } = await atomicFiClient.get<RuleFile>(`/api/rules/${ruleType}/${encodeURIComponent(name)}`);
  return data;
}

export async function saveRule(ruleType: RuleType, name: string, content: RuleFile): Promise<void> {
  await atomicFiClient.put(`/api/rules/${ruleType}/${encodeURIComponent(name)}`, content);
}

export async function deleteRule(ruleType: RuleType, name: string): Promise<void> {
  await atomicFiClient.delete(`/api/rules/${ruleType}/${encodeURIComponent(name)}`);
}
