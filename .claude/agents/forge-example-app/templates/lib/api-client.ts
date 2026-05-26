/**
 * Template for src/lib/api.ts.
 *
 * The forge-example-app agent rewrites this file with one typed function
 * per endpoint the use case actually touches. Types are hand-derived from
 * the live OpenAPI spec at GET http://localhost:4100/api/openapi — do NOT
 * codegen a 4MB client.
 *
 * Auth: bearer-only. Every scaffolded app ships with the Lotus dashboard
 * embedded, which requires POST /api/lotus/embed-token, which requires a
 * human bearer session. LoginGate collects credentials at boot and stores
 * the bearer in sessionStorage; this client picks it up.
 *
 * No silent fallbacks: throw on non-2xx with status + body so the demo
 * surfaces errors loudly (matches atomic-fi's "fail loud" philosophy).
 */

import { getStoredBearer } from "./session";

const API_BASE = "";

function authHeaders(): Record<string, string> {
  const bearer = getStoredBearer();
  if (!bearer) throw new Error("Not signed in. LoginGate must run first.");
  return { authorization: `Bearer ${bearer}` };
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers: {
      "content-type": "application/json",
      ...authHeaders(),
      ...(init.headers ?? {}),
    },
  });
  if (!res.ok) {
    throw new Error(`${init.method ?? "GET"} ${path}: ${res.status} ${await res.text()}`);
  }
  return res.json() as Promise<T>;
}

// Add one typed function per endpoint below. Example shape — DELETE
// this stub before shipping and replace with the real endpoints the
// use case needs:
//
// export type CreateAccountHolderRequest = { /* from spec */ };
// export type AccountHolderResponse     = { /* from spec */ };
//
// export function createAccountHolder(
//   body: CreateAccountHolderRequest,
// ): Promise<AccountHolderResponse> {
//   return request("/api/account-holders", {
//     method: "POST",
//     body: JSON.stringify(body),
//   });
// }

export { request };
