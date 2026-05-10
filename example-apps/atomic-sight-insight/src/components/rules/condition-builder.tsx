import { Plus, Trash2 } from "lucide-react";
import type { RuleCondition, RuleConditionGroup, RuleNode, RuleScope, RuleOperator } from "@/api/types";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Slider } from "@/components/ui/slider";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { fieldDef, fieldsForScope, operatorsForType } from "@/lib/rules/schema";
import { newCondition, newGroup } from "@/lib/rules/engine";
import { cn } from "@/lib/utils";

interface Props {
  scope: RuleScope;
  group: RuleConditionGroup;
  onChange: (g: RuleConditionGroup) => void;
  depth?: number;
}

export function ConditionBuilder({ scope, group, onChange, depth = 0 }: Props) {
  const updateChild = (id: string, next: RuleNode | null) => {
    const children = next === null
      ? group.children.filter((c) => c.id !== id)
      : group.children.map((c) => (c.id === id ? next : c));
    onChange({ ...group, children });
  };

  return (
    <div className={cn("rounded-md border p-2", depth === 0 ? "bg-muted/30" : "bg-background")}>
      <div className="mb-2 flex items-center gap-2">
        <Select value={group.combinator} onValueChange={(v) => onChange({ ...group, combinator: v as "AND" | "OR" })}>
          <SelectTrigger className="h-7 w-[80px]"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="AND">ALL of</SelectItem>
            <SelectItem value="OR">ANY of</SelectItem>
          </SelectContent>
        </Select>
        <span className="text-[11px] text-muted-foreground">the following must match</span>
      </div>

      <div className="space-y-2">
        {group.children.map((c) =>
          c.kind === "condition" ? (
            <ConditionRow
              key={c.id}
              scope={scope}
              cond={c}
              onChange={(next) => updateChild(c.id, next)}
              onRemove={() => updateChild(c.id, null)}
            />
          ) : (
            <div key={c.id} className="flex gap-2">
              <div className="flex-1">
                <ConditionBuilder
                  scope={scope}
                  group={c}
                  onChange={(g) => updateChild(c.id, g)}
                  depth={depth + 1}
                />
              </div>
              <Button variant="ghost" size="icon" className="h-7 w-7 shrink-0" onClick={() => updateChild(c.id, null)}>
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            </div>
          ),
        )}
      </div>

      <div className="mt-2 flex gap-2">
        <Button size="sm" variant="outline" className="h-7 gap-1.5" onClick={() => onChange({ ...group, children: [...group.children, newCondition(fieldsForScope(scope)[0].path)] })}>
          <Plus className="h-3 w-3" /> Condition
        </Button>
        {depth < 2 && (
          <Button size="sm" variant="outline" className="h-7 gap-1.5" onClick={() => onChange({ ...group, children: [...group.children, newGroup("OR")] })}>
            <Plus className="h-3 w-3" /> Group
          </Button>
        )}
      </div>
    </div>
  );
}

function ConditionRow({
  scope, cond, onChange, onRemove,
}: {
  scope: RuleScope;
  cond: RuleCondition;
  onChange: (c: RuleCondition) => void;
  onRemove: () => void;
}) {
  const fields = fieldsForScope(scope);
  const def = fieldDef(scope, cond.field) ?? fields[0];
  const ops = operatorsForType(def.type);

  const renderValueInput = () => {
    if (cond.operator === "exists") return <div className="text-[11px] text-muted-foreground">no value</div>;
    if (cond.operator === "between") {
      const arr = Array.isArray(cond.value) ? (cond.value as number[]) : [0, 0];
      return (
        <div className="flex gap-1">
          <Input type="number" value={arr[0] ?? ""} onChange={(e) => onChange({ ...cond, value: [Number(e.target.value), arr[1] ?? 0] })} className="h-7" />
          <Input type="number" value={arr[1] ?? ""} onChange={(e) => onChange({ ...cond, value: [arr[0] ?? 0, Number(e.target.value)] })} className="h-7" />
        </div>
      );
    }
    if (cond.operator === "in" || cond.operator === "not_in") {
      const arr = Array.isArray(cond.value) ? (cond.value as string[]) : [];
      if (def.type === "enum" && def.values) {
        return (
          <div className="flex flex-wrap gap-1">
            {def.values.map((v) => {
              const on = arr.includes(v);
              return (
                <button
                  key={v}
                  type="button"
                  onClick={() => onChange({ ...cond, value: on ? arr.filter((x) => x !== v) : [...arr, v] })}
                  className={cn(
                    "rounded border px-1.5 py-0.5 text-[10px]",
                    on ? "border-primary bg-primary/10 text-primary" : "border-border text-muted-foreground",
                  )}
                >
                  {v}
                </button>
              );
            })}
          </div>
        );
      }
      return (
        <Input
          value={arr.join(", ")}
          onChange={(e) => onChange({ ...cond, value: e.target.value.split(",").map((x) => x.trim()).filter(Boolean) })}
          placeholder="comma,separated"
          className="h-7"
        />
      );
    }
    if (def.type === "enum" && def.values) {
      return (
        <Select value={String(cond.value ?? "")} onValueChange={(v) => onChange({ ...cond, value: v })}>
          <SelectTrigger className="h-7"><SelectValue placeholder="value" /></SelectTrigger>
          <SelectContent>
            {def.values.map((v) => <SelectItem key={v} value={v}>{v}</SelectItem>)}
          </SelectContent>
        </Select>
      );
    }
    if (def.type === "boolean") {
      return (
        <Select value={String(cond.value ?? "true")} onValueChange={(v) => onChange({ ...cond, value: v === "true" })}>
          <SelectTrigger className="h-7"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="true">true</SelectItem>
            <SelectItem value="false">false</SelectItem>
          </SelectContent>
        </Select>
      );
    }
    if (def.type === "number") {
      return <Input type="number" value={typeof cond.value === "number" ? cond.value : ""} onChange={(e) => onChange({ ...cond, value: Number(e.target.value) })} className="h-7" />;
    }
    return <Input value={String(cond.value ?? "")} onChange={(e) => onChange({ ...cond, value: e.target.value })} className="h-7" />;
  };

  return (
    <div className="grid grid-cols-[1fr_110px_1.2fr_90px_24px] items-center gap-2 rounded border bg-background p-2">
      <Select value={cond.field} onValueChange={(v) => onChange({ ...cond, field: v, value: "" })}>
        <SelectTrigger className="h-7"><SelectValue /></SelectTrigger>
        <SelectContent>
          {fields.map((f) => <SelectItem key={f.path} value={f.path}>{f.label}</SelectItem>)}
        </SelectContent>
      </Select>
      <Select value={cond.operator} onValueChange={(v) => onChange({ ...cond, operator: v as RuleOperator })}>
        <SelectTrigger className="h-7"><SelectValue /></SelectTrigger>
        <SelectContent>
          {ops.map((o) => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
        </SelectContent>
      </Select>
      <div>{renderValueInput()}</div>
      <div className="flex items-center gap-1.5">
        <Slider value={[cond.weight]} min={1} max={10} step={1} onValueChange={(v) => onChange({ ...cond, weight: v[0] })} className="flex-1" />
        <span className="w-5 text-right font-mono text-[10px] text-muted-foreground">{cond.weight}</span>
      </div>
      <Button variant="ghost" size="icon" className="h-6 w-6" onClick={onRemove}>
        <Trash2 className="h-3 w-3" />
      </Button>
    </div>
  );
}
