import { useState } from "react";

const API_BASE = "";
const BACKEND_ORIGIN = "http://localhost:4100";

type AuthState =
  | { step: "login" }
  | { step: "authenticated"; bearer: string }
  | { step: "embedded"; bearer: string; embedUrl: string };

export default function App() {
  const [state, setState] = useState<AuthState>({ step: "login" });
  const [email, setEmail] = useState("admin@atomic-fi.local");
  const [password, setPassword] = useState("admin-password-dev");
  const [tenantSlug, setTenantSlug] = useState("atomic-fi-tenant");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  const login = async () => {
    setError("");
    setLoading(true);
    try {
      const res = await fetch(`${API_BASE}/api/sessions`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          email,
          password,
          tenant_slug: tenantSlug,
          expires_in: 3600,
        }),
      });
      if (!res.ok) throw new Error(`Login failed: ${res.status}`);
      const body = await res.json();
      setState({ step: "authenticated", bearer: body.bearer });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Login failed");
    } finally {
      setLoading(false);
    }
  };

  const getEmbedToken = async () => {
    if (state.step !== "authenticated") return;
    setError("");
    setLoading(true);
    try {
      const res = await fetch(`${API_BASE}/api/lotus/embed-token`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${state.bearer}`,
        },
      });
      if (!res.ok) throw new Error(`Token exchange failed: ${res.status}`);
      const body = await res.json();
      const embedUrl = `${BACKEND_ORIGIN}/lotus?token=${encodeURIComponent(body.token)}`;
      setState({ step: "embedded", bearer: state.bearer, embedUrl });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Token exchange failed");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ fontFamily: "system-ui", width: "100vw", height: "100vh", display: "flex", flexDirection: "column" }}>
      <h1>Lotus Embed — Secure iframe POC</h1>
      <p style={{ color: "#666" }}>
        Mirrors the Stripe embed pattern from SCP: login &rarr; exchange bearer
        for short-lived embed token &rarr; render in iframe.
      </p>

      {error && (
        <div style={{ background: "#fee", border: "1px solid #c00", padding: 12, borderRadius: 6, marginBottom: 16 }}>
          {error}
        </div>
      )}

      {state.step === "login" && (
        <div style={{ display: "flex", flexDirection: "column", gap: 12, maxWidth: 400 }}>
          <h2>1. Login</h2>
          <input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="Email" />
          <input value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Password" type="password" />
          <input value={tenantSlug} onChange={(e) => setTenantSlug(e.target.value)} placeholder="Tenant slug" />
          <button onClick={login} disabled={loading}>
            {loading ? "Logging in..." : "Login → Get Bearer"}
          </button>
        </div>
      )}

      {state.step === "authenticated" && (
        <div>
          <h2>2. Exchange Bearer for Embed Token</h2>
          <p style={{ fontSize: 13, color: "#666" }}>
            Bearer: <code>{state.bearer.slice(0, 20)}...</code>
          </p>
          <button onClick={getEmbedToken} disabled={loading}>
            {loading ? "Exchanging..." : "Get Embed Token → Open Lotus"}
          </button>
        </div>
      )}

      {state.step === "embedded" && (
        <div>
          <h2>3. Lotus Dashboard (iframe)</h2>
          <p style={{ fontSize: 13, color: "#666" }}>
            Embed URL: <code>{state.embedUrl.slice(0, 80)}...</code>
          </p>
          <iframe
            src={state.embedUrl}
            style={{ width: "100%", flex: 1, border: "none" }}
            title="Lotus Dashboard"
          />
          <button
            onClick={() => setState({ step: "authenticated", bearer: state.bearer })}
            style={{ marginTop: 12 }}
          >
            Refresh Token (get new embed token)
          </button>
        </div>
      )}
    </div>
  );
}
