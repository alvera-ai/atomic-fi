import axios from 'axios';
import { getStoredApiKey } from '../features/connect/api-key';

// ZenRule agent: unauthenticated, evaluates saved decisions.
// Hits /api/projects/<rule_type>/evaluate/<name> via Vite proxy → :8090.
export const zenruleClient = axios.create();

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
