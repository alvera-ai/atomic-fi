import { useEffect, useState } from "react";
import { Check, ChevronDown, Loader2, Play, Sparkles, Wand2, X } from "lucide-react";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "@/components/ui/collapsible";
import { useCopilot } from "@/contexts/copilot-context";
import { cn } from "@/lib/utils";
import { formatAmount, shortId } from "@/lib/money";

const SUGGESTIONS = [
  "Pending USD transactions over 10k",
  "Show transactions linked to sanctioned counterparties",
  "Rejected card payments",
  "All settled credit transfers",
];

export function CopilotDrawer() {
  const c = useCopilot();
  const [localPrompt, setLocalPrompt] = useState(c.prompt);

  useEffect(() => {
    setLocalPrompt(c.prompt);
  }, [c.prompt]);

  return (
    <Sheet open={c.open} onOpenChange={(v) => (v ? c.openDrawer() : c.closeDrawer())}>
      <SheetContent className="flex w-full flex-col gap-0 p-0 sm:max-w-[520px]">
        <SheetHeader className="border-b p-4">
          <SheetTitle className="flex items-center gap-2">
            <Sparkles className="h-4 w-4 text-primary" />
            Copilot
          </SheetTitle>
          <SheetDescription>
            Text-to-SQL over the AtomicFi schema. Tools used per run are shown below.
          </SheetDescription>
        </SheetHeader>

        <div className="border-b p-4">
          <Textarea
            value={localPrompt}
            onChange={(e) => setLocalPrompt(e.target.value)}
            placeholder="Ask in plain English…"
            className="min-h-[80px] resize-none"
          />
          <div className="mt-2 flex items-center justify-between gap-2">
            <div className="flex flex-wrap gap-1.5">
              {SUGGESTIONS.map((s) => (
                <button
                  key={s}
                  onClick={() => setLocalPrompt(s)}
                  className="rounded-full border bg-muted/50 px-2.5 py-0.5 text-[11px] text-muted-foreground hover:bg-muted"
                >
                  {s}
                </button>
              ))}
            </div>
            <Button
              size="sm"
              onClick={() => {
                c.setPrompt(localPrompt);
                c.run(localPrompt);
              }}
              disabled={c.isRunning || !localPrompt.trim()}
              className="gap-1.5"
            >
              {c.isRunning ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Play className="h-3.5 w-3.5" />}
              Run
            </Button>
          </div>
        </div>

        <div className="flex-1 overflow-y-auto">
          {c.steps.length === 0 && !c.resolution && (
            <div className="flex h-full flex-col items-center justify-center gap-2 px-8 text-center text-sm text-muted-foreground">
              <Wand2 className="h-8 w-8 text-muted-foreground/50" />
              Run a prompt to see the agent's tool calls and the resulting rows.
            </div>
          )}

          {c.steps.length > 0 && (
            <div className="space-y-2 p-4">
              <div className="mb-1 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
                Tool calls
              </div>
              {c.steps.map((s, i) => (
                <Collapsible key={i} defaultOpen>
                  <div className="rounded-md border bg-card">
                    <CollapsibleTrigger className="flex w-full items-center gap-2 px-3 py-2 text-left">
                      {s.state === "running" ? (
                        <Loader2 className="h-3.5 w-3.5 animate-spin text-primary" />
                      ) : (
                        <Check className="h-3.5 w-3.5 text-success" />
                      )}
                      <code className="text-xs font-medium">{s.tool}</code>
                      <span className="ml-auto truncate text-[11px] text-muted-foreground">
                        {s.state === "running" ? "running…" : s.resultPreview}
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
          )}

          {c.resolution && (
            <div className="space-y-3 p-4 pt-0">
              <div className="rounded-md border bg-card">
                <div className="border-b px-3 py-2 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
                  Generated SQL
                </div>
                <pre className="overflow-x-auto px-3 py-2 text-[11px] leading-relaxed text-foreground">
{c.resolution.sql}
                </pre>
              </div>

              <div className="rounded-md border">
                <div className="flex items-center gap-2 border-b px-3 py-2">
                  <span className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
                    Result
                  </span>
                  <Badge variant="secondary">{c.resolution.rows.length} rows</Badge>
                  <Button
                    size="sm"
                    variant="outline"
                    className="ml-auto h-7"
                    onClick={() => {
                      c.applyToView();
                      c.closeDrawer();
                    }}
                  >
                    Apply to view
                  </Button>
                </div>
                <div className="max-h-72 overflow-auto">
                  <table className="w-full text-xs">
                    <thead className="bg-muted/50 text-left text-muted-foreground">
                      <tr>
                        {c.resolution.columns.map((col) => (
                          <th key={col.key} className="px-3 py-1.5 font-medium">{col.label}</th>
                        ))}
                      </tr>
                    </thead>
                    <tbody>
                      {(c.resolution.rows as Array<Record<string, unknown>>).map((r, i) => (
                        <tr key={(r.id as string) ?? i} className="border-t">
                          {c.resolution!.columns.map((col) => {
                            const v = r[col.key];
                            const isStatus = ["status", "kyc_status", "risk_level"].includes(col.key);
                            const isMoney = col.key === "amount" && typeof r.currency === "string";
                            return (
                              <td key={col.key} className={cn("px-3 py-1.5", isMoney && "text-right font-mono")}>
                                {isStatus ? (
                                  <span className={cn("rounded px-1.5 py-0.5 text-[10px] font-medium", statusClass(String(v ?? "")))}>
                                    {String(v ?? "—")}
                                  </span>
                                ) : isMoney ? (
                                  formatAmount(Number(v ?? 0), String(r.currency))
                                ) : col.key === "id" ? (
                                  <span className="font-mono">{shortId(String(v ?? ""), 10)}</span>
                                ) : (
                                  <span className="capitalize">{String(v ?? "—").replace(/_/g, " ")}</span>
                                )}
                              </td>
                            );
                          })}
                        </tr>
                      ))}
                      {c.resolution.rows.length === 0 && (
                        <tr><td colSpan={c.resolution.columns.length} className="px-3 py-6 text-center text-muted-foreground">No rows.</td></tr>
                      )}
                    </tbody>
                  </table>
                </div>
              </div>

              <p className="text-[11px] text-muted-foreground">{c.resolution.explanation}</p>
            </div>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}

function statusClass(status: string | null): string {
  switch (status) {
    case "settled": return "bg-success/15 text-success";
    case "accepted": return "bg-info/15 text-info";
    case "pending": return "bg-warning/15 text-warning-foreground";
    case "rejected":
    case "cancelled": return "bg-destructive/15 text-destructive";
    case "reversed": return "bg-muted text-muted-foreground";
    default: return "bg-muted text-muted-foreground";
  }
}
