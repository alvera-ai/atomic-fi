// ZenRule simulator client.
//
// ZenRule listens at :8090 by default (override with VITE_ZENRULE_URL).
// In vite dev mode, /api/projects/* is proxied to ZenRule by vite.config.ts.
// In Phoenix-served prod, same-origin /api/projects/* needs a Phoenix proxy
// to ZenRule (not yet wired in this repo — use VITE_ZENRULE_URL=http://localhost:8090
// to point directly).

import type { RuleType } from "./rules-api";

const ZENRULE_BASE = (import.meta.env.VITE_ZENRULE_URL as string | undefined)?.trim() || "";

export type SimulateRequest = {
  context: Record<string, unknown>;
  trace?: boolean;
};

export type SimulateResponse = {
  result: Record<string, unknown>;
  trace?: Record<string, unknown>;
  performance?: string;
};

export async function simulateRule(
  ruleType: RuleType,
  name: string,
  context: Record<string, unknown>,
): Promise<SimulateResponse> {
  const url = `${ZENRULE_BASE}/api/projects/${ruleType}/evaluate/${encodeURIComponent(name)}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ context, trace: true } satisfies SimulateRequest),
  });
  if (!res.ok) {
    throw new Error(`simulateRule(${name}): ${res.status} ${await res.text()}`);
  }
  return (await res.json()) as SimulateResponse;
}
