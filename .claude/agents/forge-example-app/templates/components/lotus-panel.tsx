import { useEffect, useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { embedUrl, getEmbedToken } from "@/lib/lotus";

// Embedded Lotus dashboard. Mounts an iframe pointed at the backend's
// /lotus route with a short-lived embed token. Every generated app ships
// this — the demo is incomplete without an operator view, and embedding
// it here means the human running the demo can audit every API call in
// real time.
//
// The iframe `title="Lotus Dashboard"` is load-bearing: existing
// Playwright e2e tests (e.g. example-apps/lotus-embed/e2e/) match on it.
export function LotusPanel({ bearer }: { bearer: string }) {
  const [token, setToken] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    getEmbedToken(bearer)
      .then((t) => {
        if (!cancelled) setToken(t);
      })
      .catch((e: unknown) => {
        if (!cancelled) setError(e instanceof Error ? e.message : "Failed to fetch embed token");
      });
    return () => {
      cancelled = true;
    };
  }, [bearer]);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Lotus Dashboard</CardTitle>
      </CardHeader>
      <CardContent>
        {error ? (
          <div
            role="alert"
            className="rounded-md border border-destructive/50 bg-destructive/10 px-3 py-2 text-sm text-destructive"
          >
            {error}
          </div>
        ) : !token ? (
          <p className="text-sm text-muted-foreground">Fetching embed token…</p>
        ) : (
          <iframe
            src={embedUrl(token)}
            title="Lotus Dashboard"
            className="h-[70vh] w-full rounded-md border"
          />
        )}
      </CardContent>
    </Card>
  );
}
