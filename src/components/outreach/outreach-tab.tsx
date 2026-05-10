import { useEffect, useState } from "react";
import { formatDistanceToNow } from "date-fns";
import { Mail, Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { listOutreach, subscribeOutreach, type OutreachMessage, type OutreachSubjectType } from "@/api/outreach";
import { OutreachComposer } from "@/components/outreach/outreach-composer";
import { usePermission } from "@/hooks/use-permission";
import { cn } from "@/lib/utils";

const STATUS_STYLES: Record<OutreachMessage["status"], string> = {
  sent: "bg-muted text-foreground",
  responded: "bg-success/15 text-success-foreground",
  overdue: "bg-destructive/15 text-destructive",
};

export function OutreachTab({
  subjectType, subjectId, customerName, customerEmail,
}: {
  subjectType: OutreachSubjectType;
  subjectId: string;
  customerName: string;
  customerEmail: string;
}) {
  const [messages, setMessages] = useState<OutreachMessage[]>([]);
  const [open, setOpen] = useState(false);
  const canOutreach = usePermission("transaction.outreach");

  const refresh = () => {
    listOutreach(subjectType, subjectId).then(setMessages);
  };

  useEffect(() => {
    refresh();
    const unsub = subscribeOutreach(refresh);
    return () => { unsub(); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [subjectType, subjectId]);

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <div className="text-sm font-medium">Outreach history</div>
        {canOutreach && (
          <Button size="sm" onClick={() => setOpen(true)} className="gap-1.5">
            <Plus className="h-3.5 w-3.5" /> New request
          </Button>
        )}
      </div>

      {messages.length === 0 ? (
        <div className="rounded-md border border-dashed p-6 text-center text-xs text-muted-foreground">
          No outreach messages yet.
        </div>
      ) : (
        <ol className="relative space-y-3 border-l pl-4">
          {messages.map((m) => (
            <li key={m.id} className="relative">
              <span className="absolute -left-[21px] top-1.5 grid h-3 w-3 place-items-center rounded-full border-2 border-background bg-primary" />
              <div className="rounded-md border bg-card p-3">
                <div className="flex flex-wrap items-center gap-2">
                  <Mail className="h-3.5 w-3.5 text-muted-foreground" />
                  <span className="text-sm font-medium">{m.subject}</span>
                  <span className={cn("ml-auto rounded-full px-2 py-0.5 text-[10px] font-medium uppercase", STATUS_STYLES[m.status])}>
                    {m.status}
                  </span>
                </div>
                <div className="mt-1 text-[11px] text-muted-foreground">
                  Sent by <span className="font-medium text-foreground">{m.sent_by}</span>
                  {" · "}{formatDistanceToNow(new Date(m.sent_at), { addSuffix: true })}
                  {" · to "}{m.to_email}
                </div>
                <div className="mt-2 line-clamp-2 whitespace-pre-line text-xs text-muted-foreground">
                  {m.body}
                </div>
                {m.document_requests.length > 0 && (
                  <div className="mt-2 flex flex-wrap gap-1">
                    {m.document_requests.map((d) => (
                      <span key={d} className="rounded bg-muted px-1.5 py-0.5 text-[10px]">{d}</span>
                    ))}
                  </div>
                )}
              </div>
            </li>
          ))}
        </ol>
      )}

      <OutreachComposer
        open={open}
        onOpenChange={setOpen}
        subjectType={subjectType}
        subjectId={subjectId}
        customerName={customerName}
        customerEmail={customerEmail}
        onSent={refresh}
      />
    </div>
  );
}
