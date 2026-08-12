import { useState, type FormEvent } from "react";
import { LogIn } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { DEFAULT_LOGIN, login } from "@/lib/session";

// Startup gate for demos that need a bearer/human session — e.g.
// anything wiring POST /api/lotus/embed-token. For machine-only demos,
// use ConnectGate (x-api-key) instead.
export function LoginGate({ onConnected }: { onConnected: (bearer: string) => void }) {
  const [email, setEmail] = useState(DEFAULT_LOGIN.email);
  const [password, setPassword] = useState(DEFAULT_LOGIN.password);
  const [tenantSlug, setTenantSlug] = useState(DEFAULT_LOGIN.tenant_slug);
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (connecting) return;
    setConnecting(true);
    setError(null);
    try {
      const bearer = await login({ email, password, tenant_slug: tenantSlug, expires_in: 3600 });
      onConnected(bearer);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Login failed");
      setConnecting(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4">
      <Card className="w-full max-w-md">
        <CardHeader>
          <div className="flex items-center gap-3">
            <span className="flex h-9 w-9 items-center justify-center rounded-md bg-secondary">
              <LogIn className="h-4 w-4" />
            </span>
            <div>
              <CardTitle>Sign in to atomic-fi</CardTitle>
              <CardDescription>__APP_DESCRIPTION__</CardDescription>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input id="email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} disabled={connecting} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="password">Password</Label>
              <Input id="password" type="password" value={password} onChange={(e) => setPassword(e.target.value)} disabled={connecting} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="tenant">Tenant slug</Label>
              <Input id="tenant" value={tenantSlug} onChange={(e) => setTenantSlug(e.target.value)} disabled={connecting} />
            </div>

            {error && (
              <div
                role="alert"
                className="rounded-md border border-destructive/50 bg-destructive/10 px-3 py-2 text-sm text-destructive"
              >
                {error}
              </div>
            )}

            <Button type="submit" className="w-full" disabled={connecting}>
              {connecting ? "Signing in…" : "Sign in"}
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
