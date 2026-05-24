import axios from 'axios';
import { getStoredApiKey } from '../features/connect/api-key';

// ZenRule agent: unauthenticated, evaluates saved decisions.
// Hits ZenRule directly at its absolute URL — the OLD worktree got
// same-origin via a `vite dev` proxy, but the production-built bundle
// served by Phoenix can't piggyback on that. ZenRule responds with
// permissive CORS (see `local-dependencies.yaml` → `CORS_PERMISSIVE: true`),
// so the cross-origin POST from :4100 → :8090 succeeds. The URL is
// build-time env (`VITE_ZENRULE_URL`) with the local-dev default baked
// in; deployments override via a per-environment `.env`.
const ZENRULE_BASE_URL = (import.meta.env.VITE_ZENRULE_URL as string | undefined) ?? 'http://localhost:8090';
export const zenruleClient = axios.create({ baseURL: ZENRULE_BASE_URL });

// atomic-fi Phoenix REST: requires x-api-key.
// Hits /api/rules/* and /api/compliance-screenings/* on the same origin.
//
// The key is collected at startup by ConnectGate and held in
// sessionStorage for the browser tab; this interceptor attaches it to
// every request. A request may still set x-api-key explicitly (e.g.
// ConnectGate's own verify call) — that takes precedence.
export const atomicFiClient = axios.create();

atomicFiClient.interceptors.request.use((config) => {
  if (!config.headers.has('x-api-key')) {
    const key = getStoredApiKey();
    if (key) config.headers.set('x-api-key', key);
  }
  return config;
});
