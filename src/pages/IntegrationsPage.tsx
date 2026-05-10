import { useEffect, useState } from "react";
import { format } from "date-fns";
import { Bot, Check, Copy, KeyRound, Loader2, Play, Plus, RefreshCcw, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from "@/components/ui/dialog";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import {
  createApiKey, deleteApiKey, listApiKeys, listTenants, refreshBlocklistCache, updateTenant,
} from "@/api";
import type { ApiKeyResponse, TenantResponse } from "@/api/types";
import { toast } from "@/hooks/use-toast";
import { cn } from "@/lib/utils";

type AgentStep = { label: string; state: "running" | "done" };

export default function IntegrationsPage() {
  const [keys, setKeys] = useState<ApiKeyResponse[]>([]);
  const [tenants, setTenants] = useState<TenantResponse[]>([]);
  const [agentChoice, setAgentChoice] = useState<"atomic-fi-agent" | "platform-agent">("atomic-fi-agent");
  const [prompt, setPrompt] = useState("");
  const [steps, setSteps] = useState<AgentStep[]>([]);
  const [running, setRunning] = useState(false);

  useEffect(() => {
    listApiKeys().then(setKeys);
    listTenants().then(setTenants);
  }, []);

  const runAgent = async () => {
    if (!prompt.trim()) return;
    setRunning(true);
    setSteps([]);
    const plan = agentChoice === "atomic-fi-agent"
      ? [
          "Loading AtomicFi OpenAPI spec",
          "Generating React shell from base template",
          "Mapping prompt to operationIds",
          "Wiring screens to /api/transactions, /api/account-holders, …",
          "Compiling preview",
        ]
      : [
          "Subscribing to platform signal stream",
          "Drafting workflow graph (signals → rules → actions)",
          "Provisioning agent ↔ agent handoff",
          "Adding human review checkpoint",
          "Deploying to staging",
        ];
    for (const label of plan) {
      setSteps((p) => [...p, { label, state: "running" }]);
      await new Promise((r) => setTimeout(r, 600 + Math.random() * 400));
      setSteps((p) => p.map((s, i) => (i === p.length - 1 ? { ...s, state: "done" } : s)));
    }
    setRunning(false);
    toast({ title: "Agent run complete", description: "Mock — real run lives in alvera-ai/platform." });
  };

  return (
    <div className="grid h-full grid-cols-1 gap-4 overflow-y-auto p-4 xl:grid-cols-2">
      <Card className="p-4">
        <div className="mb-3 flex items-center gap-2">
          <Bot className="h-4 w-4 text-primary" />
          <h2 className="text-sm font-semibold">Run an agent</h2>
        </div>
        <div className="grid grid-cols-[180px_1fr] gap-2">
          <Select value={agentChoice} onValueChange={(v) => setAgentChoice(v as typeof agentChoice)}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="atomic-fi-agent">atomic-fi-agent</SelectItem>
              <SelectItem value="platform-agent">platform-agent</SelectItem>
            </SelectContent>
          </Select>
          <Input
            placeholder={agentChoice === "atomic-fi-agent" ? "Build me an ops console for SEPA disputes…" : "Watch for OFAC deltas and auto-suspend matched counterparties…"}
            value={prompt}
            onChange={(e) => setPrompt(e.target.value)}
          />
        </div>
        <div className="mt-2 flex justify-end">
          <Button size="sm" onClick={runAgent} disabled={running || !prompt.trim()} className="gap-1.5">
            {running ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Play className="h-3.5 w-3.5" />} Run
          </Button>
        </div>
        {steps.length > 0 && (
          <div className="mt-3 space-y-1.5 rounded-md border bg-muted/30 p-3">
            {steps.map((s, i) => (
              <div key={i} className="flex items-center gap-2 text-xs">
                {s.state === "running"
                  ? <Loader2 className="h-3.5 w-3.5 animate-spin text-primary" />
                  : <Check className="h-3.5 w-3.5 text-success" />}
                <span className={cn(s.state === "done" && "text-muted-foreground line-through")}>{s.label}</span>
              </div>
            ))}
          </div>
        )}
        <p className="mt-2 text-[11px] text-muted-foreground">Mocked — real runs are dispatched to alvera-ai/platform.</p>
      </Card>

      <Card className="p-0">
        <div className="flex items-center justify-between border-b px-4 py-2.5">
          <div className="flex items-center gap-2">
            <KeyRound className="h-4 w-4 text-muted-foreground" />
            <h2 className="text-sm font-semibold">API keys</h2>
          </div>
          <CreateKeyDialog tenants={tenants} onCreated={(k) => setKeys((prev) => [k, ...prev])} />
        </div>
        <ul>
          {keys.map((k) => (
            <li key={k.id} className="flex items-center gap-3 border-b px-4 py-2.5 last:border-b-0">
              <div className="min-w-0 flex-1">
                <div className="text-sm font-medium">{k.name}</div>
                <div className="font-mono text-[11px] text-muted-foreground">{k.id.slice(0, 12)}… · last used {k.last_used_at ? format(new Date(k.last_used_at), "yyyy-MM-dd") : "never"}</div>
              </div>
              <Button size="sm" variant="ghost" className="gap-1.5 text-destructive hover:text-destructive" onClick={async () => {
                await deleteApiKey(k.id);
                setKeys((prev) => prev.filter((x) => x.id !== k.id));
                toast({ title: "Key deleted", description: `DELETE /api/api-keys/${k.id.slice(0, 6)}` });
              }}>
                <Trash2 className="h-3.5 w-3.5" /> Revoke
              </Button>
            </li>
          ))}
          {keys.length === 0 && <li className="px-4 py-6 text-center text-xs text-muted-foreground">No keys.</li>}
        </ul>
      </Card>

      <Card className="p-0 xl:col-span-2">
        <div className="border-b px-4 py-2.5">
          <h2 className="text-sm font-semibold">Tenants</h2>
        </div>
        <table className="w-full text-sm">
          <thead className="text-left text-xs text-muted-foreground">
            <tr className="border-b">
              <th className="px-4 py-2 font-medium">Name</th>
              <th className="px-4 py-2 font-medium">Slug</th>
              <th className="px-4 py-2 font-medium">Region</th>
              <th className="px-4 py-2 font-medium">Blocklist refreshed</th>
              <th className="px-4 py-2 font-medium" />
            </tr>
          </thead>
          <tbody>
            {tenants.map((t) => (
              <tr key={t.id} className="border-b last:border-b-0">
                <td className="px-4 py-2.5">
                  <Input
                    defaultValue={t.name}
                    className="h-8 max-w-[240px]"
                    onBlur={async (e) => {
                      if (e.target.value === t.name) return;
                      const next = await updateTenant(t.id, { name: e.target.value });
                      setTenants((prev) => prev.map((x) => (x.id === next.id ? next : x)));
                      toast({ title: "Tenant updated", description: "PUT /api/tenants/{id}" });
                    }}
                  />
                </td>
                <td className="px-4 py-2.5 font-mono text-xs text-muted-foreground">{t.slug}</td>
                <td className="px-4 py-2.5 text-xs">{t.region}</td>
                <td className="px-4 py-2.5 text-xs text-muted-foreground">
                  {t.blocklist_refreshed_at ? format(new Date(t.blocklist_refreshed_at), "yyyy-MM-dd HH:mm") : "—"}
                </td>
                <td className="px-4 py-2.5 text-right">
                  <Button size="sm" variant="outline" className="gap-1.5" onClick={async () => {
                    const next = await refreshBlocklistCache(t.id);
                    setTenants((prev) => prev.map((x) => (x.id === next.id ? next : x)));
                    toast({ title: "Blocklist refreshed", description: "POST /api/tenants/refresh-blocklist-cache" });
                  }}>
                    <RefreshCcw className="h-3.5 w-3.5" /> Refresh
                  </Button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </Card>
    </div>
  );
}

function CreateKeyDialog({ tenants, onCreated }: { tenants: TenantResponse[]; onCreated: (k: ApiKeyResponse) => void }) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [tenantId, setTenantId] = useState(tenants[0]?.id ?? "");
  const [created, setCreated] = useState<ApiKeyResponse | null>(null);

  useEffect(() => {
    if (!tenantId && tenants[0]) setTenantId(tenants[0].id);
  }, [tenants, tenantId]);

  const submit = async () => {
    const k = await createApiKey({ name, tenant_id: tenantId });
    onCreated(k);
    setCreated(k);
    setName("");
  };

  return (
    <Dialog open={open} onOpenChange={(v) => { setOpen(v); if (!v) setCreated(null); }}>
      <DialogTrigger asChild>
        <Button size="sm" className="gap-1.5"><Plus className="h-3.5 w-3.5" /> New key</Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Create API key</DialogTitle>
          <DialogDescription>POST /api/api-keys. The raw key is shown once.</DialogDescription>
        </DialogHeader>
        {created ? (
          <div className="space-y-3">
            <div className="rounded-md border bg-muted p-3">
              <div className="text-[11px] text-muted-foreground">raw_key (copy now — won't be shown again)</div>
              <div className="mt-1 flex items-center gap-2">
                <code className="flex-1 break-all font-mono text-xs">{created.raw_key}</code>
                <Button size="sm" variant="outline" className="gap-1.5" onClick={() => {
                  navigator.clipboard.writeText(created.raw_key ?? "");
                  toast({ title: "Copied" });
                }}>
                  <Copy className="h-3.5 w-3.5" /> Copy
                </Button>
              </div>
            </div>
            <DialogFooter>
              <Button onClick={() => setOpen(false)}>Done</Button>
            </DialogFooter>
          </div>
        ) : (
          <>
            <div className="space-y-3">
              <div>
                <Label>Name</Label>
                <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="ops-dashboard" className="mt-1" />
              </div>
              <div>
                <Label>Tenant</Label>
                <Select value={tenantId} onValueChange={setTenantId}>
                  <SelectTrigger className="mt-1"><SelectValue placeholder="Select tenant" /></SelectTrigger>
                  <SelectContent>
                    {tenants.map((t) => <SelectItem key={t.id} value={t.id}>{t.name}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            </div>
            <DialogFooter>
              <Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button>
              <Button onClick={submit} disabled={!name.trim() || !tenantId}>Create</Button>
            </DialogFooter>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}
