import { KeyRound, Loader2 } from "lucide-react";
import { type FormEvent, useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { connectWithApiKey } from "@/features/onboarding/api";

/**
 * Startup gate: the onboarding app ships no credentials. The user pastes
 * a backend API key, which is verified against GET /api/sessions/verify.
 * On success the key is held in sessionStorage for the rest of the tab's
 * session and `onConnected` lets the app through.
 */
export function ConnectGate({ onConnected }: { onConnected: () => void }) {
  const [apiKey, setApiKey] = useState("");
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleConnect = async (event: FormEvent) => {
    event.preventDefault();
    setConnecting(true);
    setError(null);

    try {
      await connectWithApiKey(apiKey);
      onConnected();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to connect");
    } finally {
      setConnecting(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-background p-4">
      <Card className="w-full max-w-md">
        <CardHeader>
          <div className="mb-2 flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10">
            <KeyRound className="h-5 w-5 text-primary" />
          </div>
          <CardTitle>Connect to atomic-fi</CardTitle>
          <CardDescription>
            Enter a backend API key to start an onboarding session. The key is
            kept only for this browser tab and is never bundled into the app.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleConnect} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="api-key">API key</Label>
              <Input
                id="api-key"
                type="password"
                autoComplete="off"
                placeholder="Backend API key"
                value={apiKey}
                onChange={(event) => setApiKey(event.target.value)}
                disabled={connecting}
              />
            </div>

            {error && <p className="text-sm text-destructive">{error}</p>}

            <Button type="submit" className="w-full" disabled={connecting || !apiKey.trim()}>
              {connecting ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  Connecting…
                </>
              ) : (
                "Connect"
              )}
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
