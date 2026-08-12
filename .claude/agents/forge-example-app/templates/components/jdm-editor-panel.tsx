import { useEffect, useState } from "react";
import { DecisionGraph, type DecisionGraphType } from "@gorules/jdm-editor";
import "@gorules/jdm-editor/dist/style.css";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { getRule, upsertRule, type RuleType } from "@/lib/rules-api";

// Loads the JDM file the agent authored, hands it to <DecisionGraph>,
// and writes changes back to Phoenix. ZenRule hot-reloads on save so
// the change reaches the engine within ~5 seconds.
//
// The simulator panel inside <DecisionGraph> uses ZenRule directly (see
// lib/zenrule.ts) if you wire a `simulate` prop; this template keeps it
// view+edit only by default.
export function JdmEditorPanel({
  ruleType,
  ruleName,
}: {
  ruleType: RuleType;
  ruleName: string;
}) {
  const [graph, setGraph] = useState<DecisionGraphType | null>(null);
  const [dirty, setDirty] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    getRule(ruleType, ruleName)
      .then((doc) => {
        if (!cancelled) setGraph(doc as DecisionGraphType);
      })
      .catch((e: unknown) => {
        if (!cancelled) setError(e instanceof Error ? e.message : "Failed to load rule");
      });
    return () => {
      cancelled = true;
    };
  }, [ruleType, ruleName]);

  async function save() {
    if (!graph) return;
    setSaving(true);
    setError(null);
    try {
      await upsertRule(ruleType, ruleName, graph as Record<string, unknown>);
      setDirty(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to save rule");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between gap-4">
        <div>
          <CardTitle>{ruleName}</CardTitle>
          <CardDescription>
            {ruleType} · {dirty ? "Unsaved changes" : "Synced"}
          </CardDescription>
        </div>
        <Button onClick={save} disabled={!dirty || saving || !graph} size="sm">
          {saving ? "Saving…" : "Save"}
        </Button>
      </CardHeader>
      <CardContent>
        {error ? (
          <div
            role="alert"
            className="rounded-md border border-destructive/50 bg-destructive/10 px-3 py-2 text-sm text-destructive"
          >
            {error}
          </div>
        ) : !graph ? (
          <p className="text-sm text-muted-foreground">Loading rule…</p>
        ) : (
          <div className="h-[600px] w-full">
            <DecisionGraph
              value={graph}
              onChange={(next) => {
                setGraph(next);
                setDirty(true);
              }}
            />
          </div>
        )}
      </CardContent>
    </Card>
  );
}
