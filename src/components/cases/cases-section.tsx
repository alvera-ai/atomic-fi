import { useEffect, useState } from "react";
import { format } from "date-fns";
import { ArrowUpRight, Briefcase } from "lucide-react";
import { Link } from "react-router-dom";
import { Card } from "@/components/ui/card";
import { StatusPill } from "@/components/status-pill";
import { listCasesBySource, subscribeCases, type Case } from "@/api/cases";

interface Props {
  sourceId: string;
  title?: string;
  emptyText?: string;
  className?: string;
}

const PRIORITY_TONE: Record<string, string> = {
  critical: "bg-destructive text-destructive-foreground",
  high: "bg-destructive/15 text-destructive border border-destructive/30",
  medium: "bg-warning/20 text-warning-foreground border border-warning/30",
  low: "bg-muted text-muted-foreground border border-border",
};

export function CasesSection({ sourceId, title = "Cases", emptyText = "No cases linked.", className }: Props) {
  const [cases, setCases] = useState<Case[]>([]);
  useEffect(() => {
    let alive = true;
    const refresh = () => listCasesBySource(sourceId).then((c) => alive && setCases(c));
    refresh();
    const unsub = subscribeCases(refresh);
    return () => { alive = false; unsub(); };
  }, [sourceId]);

  return (
    <Card className={className ?? "p-0"}>
      <div className="flex items-center gap-2 border-b px-3 py-2">
        <Briefcase className="h-3.5 w-3.5 text-muted-foreground" />
        <div className="text-sm font-medium">{title}</div>
        <span className="ml-auto text-xs text-muted-foreground">{cases.length}</span>
      </div>
      {cases.length === 0 ? (
        <div className="px-3 py-4 text-xs text-muted-foreground">{emptyText}</div>
      ) : (
        <ul>
          {cases.map((c) => (
            <li key={c.id} className="border-b last:border-b-0">
              <Link
                to={`/cases?focus=${c.id}`}
                className="grid grid-cols-[auto_1fr_auto] items-center gap-2 px-3 py-2 text-xs transition hover:bg-muted/40"
              >
                <span className={`rounded-full px-1.5 py-0.5 text-[10px] font-medium capitalize ${PRIORITY_TONE[c.priority]}`}>
                  {c.priority}
                </span>
                <div className="min-w-0">
                  <div className="truncate font-medium">{c.title}</div>
                  <div className="text-[11px] text-muted-foreground">
                    {c.id} · {c.type.replace(/_/g, " ")} · {c.assigned_to} · due {format(new Date(c.due_date), "yyyy-MM-dd")}
                  </div>
                </div>
                <div className="flex items-center gap-1">
                  <StatusPill value={c.status} />
                  <ArrowUpRight className="h-3 w-3 text-muted-foreground" />
                </div>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}
