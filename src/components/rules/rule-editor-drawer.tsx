import { useEffect, useState } from "react";
import { format } from "date-fns";
import { Archive, Copy, Rocket, RotateCcw, Save, Trash2 } from "lucide-react";
import type { Rule, RuleAction, RuleScope, RuleSeverity } from "@/api/types";
import {
  Sheet, SheetContent, SheetHeader, SheetTitle,
} from "@/components/ui/sheet";
import {
  Tabs, TabsContent, TabsList, TabsTrigger,
} from "@/components/ui/tabs";
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import {
  Tooltip, TooltipContent, TooltipProvider, TooltipTrigger,
} from "@/components/ui/tooltip";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Slider } from "@/components/ui/slider";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { StatusPill } from "@/components/status-pill";
import { JdmGraphEditor } from "@/components/rules/jdm-graph-editor";
import { SandboxRunner } from "@/components/rules/sandbox-runner";
import { BacktestTab } from "@/components/rules/backtest-tab";
import { newGroup } from "@/lib/rules/engine";
import { conditionTreeToJdm, emptyJdmGraph } from "@/lib/rules/jdm";
import { archiveRule, createRule, deleteRule, promoteRule, restoreRule, saveRule } from "@/api/rules";
import { toast } from "@/hooks/use-toast";
import { usePermission } from "@/hooks/use-permission";
import { useAuth } from "@/contexts/auth-context";
import { useAuditLogger } from "@/hooks/use-audit-logger";
import { cn } from "@/lib/utils";

const emptyRule = (): Rule => ({
  id: crypto.randomUUID(),
  name: "New rule",
  description: "",
  scope: "transaction",
  status: "sandbox",
  severity: "medium",
  action: "flag",
  threshold: 0.5,
  when: newGroup("AND"),
  content: emptyJdmGraph(),
  tags: [],
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
  created_by: "you@alvera.ai",
  version: 1,
});

interface Props {
  rule: Rule | null;
  isNew?: boolean;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onChanged: () => void;
}

export function RuleEditorDrawer({ rule, isNew, open, onOpenChange, onChanged }: Props) {
  const [draft, setDraft] = useState<Rule>(rule ?? emptyRule());
  const [showJson, setShowJson] = useState(false);
  const [saving, setSaving] = useState(false);
  const [confirmPromote, setConfirmPromote] = useState(false);
  const [confirmArchive, setConfirmArchive] = useState(false);

  const { user } = useAuth();
  const logAudit = useAuditLogger();
  const canCreate = usePermission("rule.create");
  const canPromote = usePermission("rule.promote");
  const canArchive = usePermission("rule.archive");
  const canBacktest = usePermission("rule.backtest");
  const canEdit = isNew ? canCreate : canCreate; // editing rules requires create permission
  const readOnly = !canEdit;

  useEffect(() => {
    if (rule) setDraft(rule);
    else if (isNew) setDraft(emptyRule());
  }, [rule, isNew, open]);

  const update = (patch: Partial<Rule>) => {
    if (readOnly) return;
    setDraft((d) => ({ ...d, ...patch }));
  };

  const save = async () => {
    if (readOnly) return;
    setSaving(true);
    try {
      if (isNew) {
        await createRule({ ...draft });
        logAudit({
          action_type: "rule.created",
          resource_type: "rule",
          resource_id: draft.id,
          description: `Created rule '${draft.name}'`,
          metadata: { status: draft.status },
        });
        toast({ title: "Rule created", description: `POST /rules · status: ${draft.status}` });
      } else {
        await saveRule(draft);
        logAudit({
          action_type: "rule.edited",
          resource_type: "rule",
          resource_id: draft.id,
          description: `Edited rule '${draft.name}'`,
          metadata: {},
        });
        toast({ title: "Rule saved", description: `PUT /rules/${draft.id.slice(0, 6)}` });
      }
      onChanged(); onOpenChange(false);
    } finally { setSaving(false); }
  };

  const doPromote = async () => {
    await promoteRule(draft.id, user.name);
    logAudit({
      action_type: "rule.promoted",
      resource_type: "rule",
      resource_id: draft.id,
      description: `Promoted rule '${draft.name}' from Sandbox to Live`,
      metadata: { from: "sandbox", to: "live" },
    });
    toast({ title: "Promoted to live", description: `By ${user.name}` });
    setConfirmPromote(false);
    onChanged(); onOpenChange(false);
  };
  const doArchive = async () => {
    await archiveRule(draft.id);
    logAudit({
      action_type: "rule.archived",
      resource_type: "rule",
      resource_id: draft.id,
      description: `Archived rule '${draft.name}'`,
      metadata: {},
    });
    toast({ title: "Archived" });
    setConfirmArchive(false);
    onChanged(); onOpenChange(false);
  };
  const restore = async () => { await restoreRule(draft.id); toast({ title: "Restored to sandbox" }); onChanged(); onOpenChange(false); };
  const remove = async () => {
    if (!confirm("Delete this rule? This cannot be undone.")) return;
    await deleteRule(draft.id); toast({ title: "Deleted" }); onChanged(); onOpenChange(false);
  };

  const lastPromoted = draft.last_promoted_at
    ? `${draft.last_promoted_by ?? "unknown"} · ${format(new Date(draft.last_promoted_at), "yyyy-MM-dd HH:mm")}`
    : "Never promoted";


  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="right" className="flex w-full flex-col gap-0 p-0 sm:max-w-[1100px]">
        <SheetHeader className="space-y-2 border-b p-4">
          {readOnly && (
            <div className="rounded-md border border-dashed bg-muted/40 px-2.5 py-1.5 text-[11px] text-muted-foreground">
              You have read-only access to rules.
            </div>
          )}
          <div className="flex items-start gap-2">
            <TooltipProvider>
              <Tooltip>
                <TooltipTrigger asChild>
                  <Input
                    value={draft.name}
                    onChange={(e) => update({ name: e.target.value })}
                    disabled={readOnly}
                    className="h-8 flex-1 text-base font-semibold"
                  />
                </TooltipTrigger>
                {readOnly && <TooltipContent>You have read-only access to rules.</TooltipContent>}
              </Tooltip>
            </TooltipProvider>
            <StatusPill value={draft.status} />
          </div>
          <SheetTitle className="sr-only">Edit rule</SheetTitle>
          <div className="text-[11px] text-muted-foreground">
            <span className="font-medium text-foreground">Last promoted:</span> {lastPromoted}
          </div>
          <div className="flex flex-wrap items-center gap-1.5">
            {!isNew && draft.status === "sandbox" && canPromote && (
              <Button size="sm" onClick={() => setConfirmPromote(true)} className="gap-1.5">
                <Rocket className="h-3.5 w-3.5" /> Promote to live
              </Button>
            )}
            {!isNew && draft.status === "live" && canArchive && (
              <Button size="sm" variant="outline" onClick={() => setConfirmArchive(true)} className="gap-1.5">
                <Archive className="h-3.5 w-3.5" /> Archive
              </Button>
            )}
            {!isNew && draft.status === "sandbox" && canArchive && (
              <Button size="sm" variant="outline" onClick={() => setConfirmArchive(true)} className="gap-1.5">
                <Archive className="h-3.5 w-3.5" /> Archive
              </Button>
            )}
            {!isNew && draft.status === "archived" && canArchive && (
              <Button size="sm" variant="outline" onClick={restore} className="gap-1.5">
                <RotateCcw className="h-3.5 w-3.5" /> Restore to sandbox
              </Button>
            )}
            {!readOnly && (
              <Button size="sm" onClick={save} disabled={saving} className="gap-1.5">
                <Save className="h-3.5 w-3.5" /> {saving ? "Saving…" : "Save"}
              </Button>
            )}
            {!isNew && canArchive && (
              <Button size="sm" variant="ghost" onClick={remove} className="ml-auto gap-1.5 text-destructive">
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            )}
          </div>
        </SheetHeader>

        <Tabs defaultValue="definition" className="flex min-h-0 flex-1 flex-col">
          <TabsList className={cn("mx-4 mt-3 grid w-auto", canBacktest && !isNew ? "grid-cols-4" : "grid-cols-3")}>
            <TabsTrigger value="definition">Definition</TabsTrigger>
            <TabsTrigger value="settings">Settings</TabsTrigger>
            <TabsTrigger value="sandbox">Sandbox</TabsTrigger>
            {canBacktest && !isNew && <TabsTrigger value="backtest">Backtest</TabsTrigger>}
          </TabsList>

          <div className="min-h-0 flex-1 overflow-y-auto p-4">
            <TabsContent value="definition" className="m-0 space-y-3">
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <Label className="text-[11px]">Scope</Label>
                  <Select
                    value={draft.scope}
                    onValueChange={(v) => update({ scope: v as RuleScope })}
                    disabled={readOnly}
                  >
                    <SelectTrigger className="h-8"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="transaction">Transaction</SelectItem>
                      <SelectItem value="account_holder">Account holder</SelectItem>
                    </SelectContent>
                  </Select>
                  <div className="mt-1 text-[10px] text-muted-foreground">
                    Logical scope. Input fields are arbitrary — declare any path in the decision table.
                  </div>
                </div>
                <div className="flex items-end justify-end gap-2">
                  <Label className="text-[11px]">JSON view</Label>
                  <Switch checked={showJson} onCheckedChange={setShowJson} />
                </div>
              </div>

              {showJson ? (
                <div className="space-y-2">
                  <Textarea
                    value={JSON.stringify(draft.content ?? conditionTreeToJdm(draft.when, draft.name), null, 2)}
                    onChange={(e) => {
                      try { update({ content: JSON.parse(e.target.value) }); } catch { /* ignore */ }
                    }}
                    readOnly={readOnly}
                    className="min-h-[420px] font-mono text-[11px]"
                  />
                  <Button
                    size="sm" variant="outline" className="gap-1.5"
                    onClick={() => navigator.clipboard.writeText(JSON.stringify(draft.content ?? {}, null, 2))}
                  >
                    <Copy className="h-3.5 w-3.5" /> Copy JDM
                  </Button>
                </div>
              ) : (
                <div className={readOnly ? "pointer-events-none opacity-70" : undefined}>
                  <JdmGraphEditor
                    value={draft.content ?? conditionTreeToJdm(draft.when, draft.name)}
                    onChange={(g) => update({ content: g })}
                  />
                </div>
              )}
            </TabsContent>

            <TabsContent value="settings" className="m-0 space-y-3">
              <div>
                <Label className="text-[11px]">Description</Label>
                <Textarea value={draft.description} onChange={(e) => update({ description: e.target.value })} readOnly={readOnly} className="mt-1" />
              </div>
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <Label className="text-[11px]">Severity</Label>
                  <Select value={draft.severity} onValueChange={(v) => update({ severity: v as RuleSeverity })} disabled={readOnly}>
                    <SelectTrigger className="h-8"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {(["low", "medium", "high", "critical"] as const).map((s) => <SelectItem key={s} value={s}>{s}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div>
                  <Label className="text-[11px]">Action</Label>
                  <Select value={draft.action} onValueChange={(v) => update({ action: v as RuleAction })} disabled={readOnly}>
                    <SelectTrigger className="h-8"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {(["flag", "review", "block"] as const).map((s) => <SelectItem key={s} value={s}>{s}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
              </div>
              <div>
                <Label className="text-[11px]">Threshold ({Math.round(draft.threshold * 100)}%)</Label>
                <Slider value={[draft.threshold * 100]} min={0} max={100} step={5} onValueChange={(v) => update({ threshold: v[0] / 100 })} disabled={readOnly} className="mt-2" />
                <div className="mt-1 text-[11px] text-muted-foreground">Hit fires only when matched-weight ratio ≥ threshold.</div>
              </div>
              <div>
                <Label className="text-[11px]">Tags (comma-separated)</Label>
                <Input value={draft.tags.join(", ")} onChange={(e) => update({ tags: e.target.value.split(",").map((t) => t.trim()).filter(Boolean) })} readOnly={readOnly} className="h-8" />
              </div>
            </TabsContent>

            <TabsContent value="sandbox" className="m-0">
              <SandboxRunner rule={draft} />
            </TabsContent>

            {canBacktest && !isNew && (
              <TabsContent value="backtest" className="m-0">
                <BacktestTab rule={draft} onPromoted={() => { onChanged(); onOpenChange(false); }} />
              </TabsContent>
            )}
          </div>
        </Tabs>
      </SheetContent>

      <AlertDialog open={confirmPromote} onOpenChange={setConfirmPromote}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Promote this rule to Live?</AlertDialogTitle>
            <AlertDialogDescription>
              It will immediately apply to all transactions and account holders.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={doPromote}>Promote to live</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <AlertDialog open={confirmArchive} onOpenChange={setConfirmArchive}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Archive this rule?</AlertDialogTitle>
            <AlertDialogDescription>
              The rule will stop evaluating. You can restore it later from the Archived tab.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={doArchive}>Archive</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </Sheet>
  );
}

