import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { format, formatDistanceToNow } from "date-fns";
import { CalendarIcon, Download, Filter, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Calendar } from "@/components/ui/calendar";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { Checkbox } from "@/components/ui/checkbox";
import { cn } from "@/lib/utils";
import {
  ACTION_TYPES, RESOURCE_ROUTE, RESOURCE_TYPES,
  listAuditEntries, subscribeAudit,
  type AuditEntry, type AuditActionType, type AuditResourceType,
} from "@/api/audit";
import { usePermission } from "@/hooks/use-permission";
import { shortId } from "@/lib/money";
import { toast as sonnerToast } from "sonner";

const ROLE_BADGE: Record<string, string> = {
  compliance_officer: "bg-primary/10 text-primary",
  compliance_analyst: "bg-blue-500/10 text-blue-700 dark:text-blue-300",
  compliance_ops_agent: "bg-emerald-500/10 text-emerald-700 dark:text-emerald-300",
  rules_manager: "bg-purple-500/10 text-purple-700 dark:text-purple-300",
  engineer: "bg-orange-500/10 text-orange-700 dark:text-orange-300",
  auditor: "bg-muted text-foreground",
};

function exportCsv(rows: AuditEntry[]) {
  const headers = ["timestamp", "actor_name", "actor_role", "action_type", "resource_type", "resource_id", "description"];
  const escape = (v: string) => `"${String(v).replace(/"/g, '""')}"`;
  const csv = [
    headers.join(","),
    ...rows.map((r) => [r.timestamp, r.actor_name, r.actor_role, r.action_type, r.resource_type, r.resource_id, r.description].map(escape).join(",")),
  ].join("\n");
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `audit-log-${new Date().toISOString().slice(0, 10)}.csv`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

export default function AuditPage() {
  const [entries, setEntries] = useState<AuditEntry[]>([]);
  const [from, setFrom] = useState<Date | undefined>();
  const [to, setTo] = useState<Date | undefined>();
  const [actions, setActions] = useState<AuditActionType[]>([]);
  const [actor, setActor] = useState("");
  const [resourceType, setResourceType] = useState<AuditResourceType | "all">("all");
  const canExport = usePermission("audit.export");

  useEffect(() => {
    const refresh = () => listAuditEntries().then(setEntries);
    refresh();
    const unsub = subscribeAudit(refresh);
    return () => { unsub(); };
  }, []);

  const filtered = useMemo(() => {
    return entries.filter((e) => {
      const ts = new Date(e.timestamp).getTime();
      if (from && ts < from.setHours(0, 0, 0, 0)) return false;
      if (to && ts > new Date(to).setHours(23, 59, 59, 999)) return false;
      if (actions.length > 0 && !actions.includes(e.action_type)) return false;
      if (actor && !e.actor_name.toLowerCase().includes(actor.toLowerCase())) return false;
      if (resourceType !== "all" && e.resource_type !== resourceType) return false;
      return true;
    });
  }, [entries, from, to, actions, actor, resourceType]);

  const toggleAction = (a: AuditActionType) =>
    setActions((prev) => (prev.includes(a) ? prev.filter((x) => x !== a) : [...prev, a]));

  const clearFilters = () => {
    setFrom(undefined); setTo(undefined); setActions([]); setActor(""); setResourceType("all");
  };

  return (
    <div className="flex h-full flex-col">
      <div className="flex items-start justify-between border-b p-4">
        <div>
          <h1 className="text-lg font-semibold tracking-tight">Audit log</h1>
          <p className="text-xs text-muted-foreground">
            {filtered.length} of {entries.length} entries · all significant actions across the platform
          </p>
        </div>
        {canExport && (
          <Button size="sm" variant="outline" onClick={() => exportCsv(filtered)} className="gap-1.5">
            <Download className="h-3.5 w-3.5" /> Export CSV
          </Button>
        )}
      </div>

      <Card className="m-4 mb-0 p-3">
        <div className="flex flex-wrap items-end gap-3">
          <div className="space-y-1">
            <Label className="text-[11px] text-muted-foreground">From</Label>
            <DatePopover date={from} onChange={setFrom} placeholder="Start date" />
          </div>
          <div className="space-y-1">
            <Label className="text-[11px] text-muted-foreground">To</Label>
            <DatePopover date={to} onChange={setTo} placeholder="End date" />
          </div>

          <div className="space-y-1">
            <Label className="text-[11px] text-muted-foreground">Action type</Label>
            <Popover>
              <PopoverTrigger asChild>
                <Button variant="outline" size="sm" className="h-9 w-[200px] justify-start gap-1.5">
                  <Filter className="h-3.5 w-3.5" />
                  {actions.length === 0 ? "All actions" : `${actions.length} selected`}
                </Button>
              </PopoverTrigger>
              <PopoverContent align="start" className="w-[260px] p-2">
                <div className="max-h-[280px] space-y-1 overflow-y-auto">
                  {ACTION_TYPES.map((a) => (
                    <label key={a} className="flex cursor-pointer items-center gap-2 rounded px-2 py-1 text-xs hover:bg-muted">
                      <Checkbox checked={actions.includes(a)} onCheckedChange={() => toggleAction(a)} />
                      <span className="font-mono">{a}</span>
                    </label>
                  ))}
                </div>
              </PopoverContent>
            </Popover>
          </div>

          <div className="space-y-1">
            <Label className="text-[11px] text-muted-foreground">Actor</Label>
            <Input value={actor} onChange={(e) => setActor(e.target.value)} placeholder="Search actor…" className="h-9 w-[180px]" />
          </div>

          <div className="space-y-1">
            <Label className="text-[11px] text-muted-foreground">Resource type</Label>
            <Select value={resourceType} onValueChange={(v) => setResourceType(v as typeof resourceType)}>
              <SelectTrigger className="h-9 w-[160px]"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All resources</SelectItem>
                {RESOURCE_TYPES.map((r) => <SelectItem key={r} value={r}>{r.replace(/_/g, " ")}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>

          <Button variant="ghost" size="sm" onClick={clearFilters} className="ml-auto gap-1.5 text-muted-foreground">
            <X className="h-3.5 w-3.5" /> Clear
          </Button>
        </div>
      </Card>

      <div className="min-h-0 flex-1 overflow-auto p-4">
        <Card className="overflow-hidden">
          <table className="w-full text-xs">
            <thead className="bg-muted/40 text-[10px] uppercase tracking-wide text-muted-foreground">
              <tr>
                <th className="px-3 py-2 text-left font-medium">Timestamp</th>
                <th className="px-3 py-2 text-left font-medium">Actor</th>
                <th className="px-3 py-2 text-left font-medium">Role</th>
                <th className="px-3 py-2 text-left font-medium">Action</th>
                <th className="px-3 py-2 text-left font-medium">Resource</th>
                <th className="px-3 py-2 text-left font-medium">Description</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((e) => (
                <tr key={e.id} className="border-t hover:bg-muted/30">
                  <td className="px-3 py-2 align-top">
                    <div className="font-mono">{format(new Date(e.timestamp), "yyyy-MM-dd HH:mm")}</div>
                    <div className="text-[10px] text-muted-foreground">
                      {formatDistanceToNow(new Date(e.timestamp), { addSuffix: true })}
                    </div>
                  </td>
                  <td className="px-3 py-2 align-top font-medium">{e.actor_name}</td>
                  <td className="px-3 py-2 align-top">
                    <span className={cn("rounded px-1.5 py-0.5 text-[10px] font-medium", ROLE_BADGE[e.actor_role] ?? "bg-muted")}>
                      {e.actor_role.replace(/_/g, " ")}
                    </span>
                  </td>
                  <td className="px-3 py-2 align-top font-mono text-[11px]">{e.action_type}</td>
                  <td className="px-3 py-2 align-top">
                    <Link
                      to={RESOURCE_ROUTE[e.resource_type]}
                      onClick={() => sonnerToast.info(`${e.resource_type}: ${e.resource_id}`)}
                      className="text-primary hover:underline"
                    >
                      {e.resource_type}/{shortId(e.resource_id, 8)}
                    </Link>
                  </td>
                  <td className="px-3 py-2 align-top text-muted-foreground">{e.description}</td>
                </tr>
              ))}
              {filtered.length === 0 && (
                <tr><td colSpan={6} className="px-3 py-8 text-center text-muted-foreground">No matching entries.</td></tr>
              )}
            </tbody>
          </table>
        </Card>
      </div>
    </div>
  );
}

function DatePopover({
  date, onChange, placeholder,
}: { date: Date | undefined; onChange: (d: Date | undefined) => void; placeholder: string }) {
  return (
    <Popover>
      <PopoverTrigger asChild>
        <Button
          variant="outline"
          size="sm"
          className={cn("h-9 w-[160px] justify-start gap-1.5 font-normal", !date && "text-muted-foreground")}
        >
          <CalendarIcon className="h-3.5 w-3.5" />
          {date ? format(date, "PP") : placeholder}
        </Button>
      </PopoverTrigger>
      <PopoverContent className="w-auto p-0" align="start">
        <Calendar
          mode="single"
          selected={date}
          onSelect={onChange}
          initialFocus
          className={cn("p-3 pointer-events-auto")}
        />
      </PopoverContent>
    </Popover>
  );
}
