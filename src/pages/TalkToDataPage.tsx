import { useState } from "react";
import { Check, Loader2, Play, Sparkles, Wand2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import {
  Collapsible, CollapsibleContent, CollapsibleTrigger,
} from "@/components/ui/collapsible";
import { resolveNlQuery, type CopilotResolution } from "@/lib/nlQuery";
import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";
import { formatAmount, shortId } from "@/lib/money";

const SUGGESTIONS = [
  "All high-risk account holders",
  "Open KYC requirements",
  "All sanctions matches",
  "Blocked counterparties",
  "Pending USD transactions over 10k",
];

type Step = { label: string; tool: string; state: "running" | "done"; preview: string; args: unknown };

export default function TalkToDataPage() {
  const [prompt, setPrompt] = useState("");
  const [running, setRunning] = useState(false);
  const [steps, setSteps] = useState<Step[]>([]);
  const [resolution, setResolution] = useState<CopilotResolution | null>(null);

  const run = async (text: string) => {
    if (!text.trim()) return;
    setRunning(true); setResolution(null); setSteps([]);
    const res = resolveNlQuery(text);
    for (const s of res.steps) {
      setSteps((p) => [...p, { label: s.tool, tool: s.tool, state: "running", preview: s.resultPreview, args: s.args }]);
      await new Promise((r) => setTimeout(r, 380 + Math.random() * 220));
      setSteps((p) => p.map((x, i) => (i === p.length - 1 ? { ...x, state: "done" } : x)));
    }
    setResolution(res);
    setRunning(false);
  };

  return (
    <div className="flex h-full flex-col gap-4 overflow-y-auto p-4">
      <div>
        <h1 className="text-xl font-semibold tracking-tight">Talk to data</h1>
        <p className="text-xs text-muted-foreground">Cross-table NL queries. Same Copilot tools, no scope, no persistence.</p>
      </div>

      <Card className="p-4">
        <Textarea
          value={prompt}
          onChange={(e) => setPrompt(e.target.value)}
          placeholder="Ask anything across the AtomicFi schema…"
          className="min-h-[88px]"
        />
        <div className="mt-2 flex flex-wrap items-center gap-2">
          <div className="flex flex-wrap gap-1.5">
            {SUGGESTIONS.map((s) => (
              <button key={s} onClick={() => setPrompt(s)} className="rounded-full border bg-muted/50 px-2.5 py-0.5 text-[11px] text-muted-foreground hover:bg-muted">
                {s}
              </button>
            ))}
          </div>
          <Button className="ml-auto gap-1.5" size="sm" onClick={() => run(prompt)} disabled={!prompt.trim() || running}>
            {running ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Play className="h-3.5 w-3.5" />} Run
          </Button>
        </div>
      </Card>

      {steps.length === 0 && !resolution && (
        <Card className="flex flex-col items-center justify-center gap-2 p-12 text-center text-sm text-muted-foreground">
          <Wand2 className="h-8 w-8 text-muted-foreground/50" />
          Run a prompt to see tool calls and the resulting rows.
        </Card>
      )}

      {steps.length > 0 && (
        <Card className="p-3">
          <div className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">Tool calls</div>
          <div className="space-y-2">
            {steps.map((s, i) => (
              <Collapsible key={i} defaultOpen>
                <div className="rounded-md border bg-card">
                  <CollapsibleTrigger className="flex w-full items-center gap-2 px-3 py-2 text-left">
                    {s.state === "running"
                      ? <Loader2 className="h-3.5 w-3.5 animate-spin text-primary" />
                      : <Check className="h-3.5 w-3.5 text-success" />}
                    <code className="text-xs font-medium">{s.tool}</code>
                    <span className="ml-auto truncate text-[11px] text-muted-foreground">
                      {s.state === "running" ? "running…" : s.preview}
                    </span>
                    <ChevronDown className="h-3.5 w-3.5 text-muted-foreground" />
                  </CollapsibleTrigger>
                  <CollapsibleContent>
                    <div className="border-t bg-muted/30 px-3 py-2">
                      <pre className="overflow-x-auto text-[11px] leading-snug text-muted-foreground">
{JSON.stringify(s.args, null, 2)}
                      </pre>
                    </div>
                  </CollapsibleContent>
                </div>
              </Collapsible>
            ))}
          </div>
        </Card>
      )}

      {resolution && (
        <>
          <Card className="p-0">
            <div className="border-b px-4 py-2.5 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">Generated SQL</div>
            <pre className="overflow-x-auto px-4 py-3 text-xs leading-relaxed">{resolution.sql}</pre>
          </Card>

          <Card className="p-0">
            <div className="flex items-center gap-2 border-b px-4 py-2.5">
              <Sparkles className="h-3.5 w-3.5 text-primary" />
              <span className="text-sm font-medium">Result</span>
              <Badge variant="secondary">{resolution.rows.length} rows</Badge>
              <span className="ml-auto text-[11px] text-muted-foreground">{resolution.primaryTable}</span>
            </div>
            <div className="max-h-[420px] overflow-auto">
              <table className="w-full text-xs">
                <thead className="sticky top-0 bg-muted/50 text-left text-muted-foreground">
                  <tr>
                    {resolution.columns.map((col) => (
                      <th key={col.key} className="px-3 py-1.5 font-medium">{col.label}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {(resolution.rows as Array<Record<string, unknown>>).map((r, i) => (
                    <tr key={(r.id as string) ?? i} className="border-t">
                      {resolution.columns.map((col) => {
                        const v = r[col.key];
                        const isMoney = col.key === "amount" && typeof r.currency === "string";
                        return (
                          <td key={col.key} className={cn("px-3 py-1.5", isMoney && "text-right font-mono")}>
                            {col.key === "id" ? (
                              <span className="font-mono">{shortId(String(v ?? ""), 12)}</span>
                            ) : isMoney ? (
                              formatAmount(Number(v ?? 0), String(r.currency))
                            ) : (
                              <span className="capitalize">{String(v ?? "—").replace(/_/g, " ")}</span>
                            )}
                          </td>
                        );
                      })}
                    </tr>
                  ))}
                  {resolution.rows.length === 0 && (
                    <tr><td colSpan={resolution.columns.length} className="px-3 py-6 text-center text-muted-foreground">No rows.</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          </Card>
          <p className="text-[11px] text-muted-foreground">{resolution.explanation}</p>
        </>
      )}
    </div>
  );
}
