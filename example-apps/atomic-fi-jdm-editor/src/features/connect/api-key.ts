import axios from 'axios';

// The editor ships no credentials. ConnectGate collects a backend API
// key, verifies it, and holds it here for the browser tab. Every
// atomic-fi REST request picks it up via the interceptor in
// helpers/clients.ts.
const API_KEY_STORAGE_KEY = 'atomic-fi:jdm-editor:api-key';

export function getStoredApiKey(): string | null {
  return sessionStorage.getItem(API_KEY_STORAGE_KEY);
}

export function clearStoredApiKey(): void {
  sessionStorage.removeItem(API_KEY_STORAGE_KEY);
}

// Verify a key against the protected GET /api/sessions/verify endpoint
// and, on success, persist it for the rest of the tab session. A bad
// key 401s and throws — ConnectGate surfaces that to the user.
//
// Uses a bare axios call (not atomicFiClient) so there is no import
// cycle: helpers/clients.ts imports getStoredApiKey from this module.
export async function connectWithApiKey(apiKey: string): Promise<void> {
  const trimmed = apiKey.trim();
  if (!trimmed) throw new Error('API key is required');
  await axios.get('/api/sessions/verify', { headers: { 'x-api-key': trimmed } });
  sessionStorage.setItem(API_KEY_STORAGE_KEY, trimmed);
}
