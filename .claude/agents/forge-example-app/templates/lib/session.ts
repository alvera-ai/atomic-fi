// Bearer/session auth: lotus-embed pattern. Use this INSTEAD of
// api-key.ts when the demo needs a human session — required for
// POST /api/lotus/embed-token and any other endpoint that takes a
// `Authorization: Bearer ...` header.
//
// The default credentials are the seeded dev creds. The agent should
// keep them prefilled in the LoginForm so the demo just works locally;
// for non-local deployments the user types real credentials.

const BEARER_STORAGE_KEY = "atomic-fi:__SLUG__:bearer";

export type SessionRequest = {
  email: string;
  password: string;
  tenant_slug: string;
  expires_in?: number;
};

export const DEFAULT_LOGIN: SessionRequest = {
  email: "admin@atomic-fi.local",
  password: "admin-password-dev",
  tenant_slug: "atomic-fi-tenant",
  expires_in: 3600,
};

export function getStoredBearer(): string | null {
  return sessionStorage.getItem(BEARER_STORAGE_KEY);
}

export function clearStoredBearer(): void {
  sessionStorage.removeItem(BEARER_STORAGE_KEY);
}

export async function login(req: SessionRequest): Promise<string> {
  const res = await fetch("/api/sessions", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(req),
  });
  if (!res.ok) {
    if (res.status === 401) {
      throw new Error("Those credentials were rejected. Check email / password / tenant.");
    }
    throw new Error(`login: ${res.status} ${await res.text()}`);
  }
  const body = (await res.json()) as { bearer: string };
  sessionStorage.setItem(BEARER_STORAGE_KEY, body.bearer);
  return body.bearer;
}
