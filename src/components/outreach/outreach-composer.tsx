import { useEffect, useState } from "react";
import { Send } from "lucide-react";
import {
  Sheet, SheetContent, SheetDescription, SheetFooter, SheetHeader, SheetTitle,
} from "@/components/ui/sheet";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Button } from "@/components/ui/button";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { Checkbox } from "@/components/ui/checkbox";
import { toast as sonnerToast } from "sonner";
import {
  DOCUMENT_REQUEST_OPTIONS, OUTREACH_TEMPLATES, sendOutreach,
  type OutreachSubjectType,
} from "@/api/outreach";
import { useAuth } from "@/contexts/auth-context";
import { useAuditLogger } from "@/hooks/use-audit-logger";
import { shortId } from "@/lib/money";

interface OutreachComposerProps {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  subjectType: OutreachSubjectType;
  subjectId: string;
  customerName: string;
  customerEmail: string;
  onSent?: () => void;
  prefilledTemplate?: string;
  prefilledDocs?: string[];
}

function applyPlaceholders(text: string, customerName: string, subjectId: string) {
  return text
    .split("[CUSTOMER_NAME]").join(customerName)
    .split("[TRANSACTION_ID]").join(shortId(subjectId, 10));
}

export function OutreachComposer({
  open, onOpenChange, subjectType, subjectId, customerName, customerEmail, onSent,
  prefilledTemplate, prefilledDocs,
}: OutreachComposerProps) {
  const { user } = useAuth();
  const logAudit = useAuditLogger();
  const [templateId, setTemplateId] = useState<string>(prefilledTemplate ?? "additional_documentation");
  const [to, setTo] = useState(customerEmail);
  const [subject, setSubject] = useState("");
  const [body, setBody] = useState("");
  const [docs, setDocs] = useState<string[]>(prefilledDocs ?? []);
  const [sending, setSending] = useState(false);

  useEffect(() => {
    if (!open) return;
    setTo(customerEmail);
    const initialTpl = prefilledTemplate ?? templateId;
    setTemplateId(initialTpl);
    const tpl = OUTREACH_TEMPLATES.find((t) => t.id === initialTpl)!;
    setSubject(applyPlaceholders(tpl.subject, customerName, subjectId));
    setBody(applyPlaceholders(tpl.body, customerName, subjectId));
    setDocs(prefilledDocs ?? []);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, customerEmail, customerName, subjectId, prefilledTemplate, prefilledDocs?.join("|")]);

  useEffect(() => {
    if (!open) return;
    const tpl = OUTREACH_TEMPLATES.find((t) => t.id === templateId)!;
    setSubject(applyPlaceholders(tpl.subject, customerName, subjectId));
    setBody(applyPlaceholders(tpl.body, customerName, subjectId));
  }, [templateId]);

  const toggleDoc = (d: string) =>
    setDocs((prev) => (prev.includes(d) ? prev.filter((x) => x !== d) : [...prev, d]));

  const submit = async () => {
    if (!to.trim() || !subject.trim() || !body.trim()) return;
    setSending(true);
    try {
      await sendOutreach({
        subject_type: subjectType,
        subject_id: subjectId,
        to_email: to.trim(),
        subject: subject.trim(),
        body: body.trim(),
        template: templateId,
        document_requests: docs,
        sent_by: user.name,
      });
      logAudit({
        action_type: "outreach.sent",
        resource_type: subjectType === "transaction" ? "transaction" : "account_holder",
        resource_id: subjectId,
        description: `Sent outreach '${subject.trim()}' to ${to.trim()}`,
        metadata: { template: templateId, document_requests: docs },
      });
      sonnerToast.success("Outreach sent", { description: `To ${to.trim()}` });
      onSent?.();
      onOpenChange(false);
    } finally {
      setSending(false);
    }
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="right" className="flex w-full flex-col gap-0 p-0 sm:max-w-lg">
        <SheetHeader className="border-b p-4">
          <SheetTitle>New information request</SheetTitle>
          <SheetDescription>Send a templated outreach to the customer.</SheetDescription>
        </SheetHeader>

        <div className="flex-1 space-y-3 overflow-y-auto p-4">
          <div className="space-y-1.5">
            <Label htmlFor="o-to">To</Label>
            <Input id="o-to" value={to} onChange={(e) => setTo(e.target.value)} />
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="o-tpl">Template</Label>
            <Select value={templateId} onValueChange={setTemplateId}>
              <SelectTrigger id="o-tpl"><SelectValue /></SelectTrigger>
              <SelectContent>
                {OUTREACH_TEMPLATES.map((t) => (
                  <SelectItem key={t.id} value={t.id}>{t.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="o-subject">Subject</Label>
            <Input id="o-subject" value={subject} onChange={(e) => setSubject(e.target.value)} />
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="o-body">Message</Label>
            <Textarea id="o-body" rows={9} value={body} onChange={(e) => setBody(e.target.value)} />
          </div>

          <div className="space-y-2">
            <Label>Attach document request checklist</Label>
            <div className="grid grid-cols-1 gap-1.5 rounded-md border p-2.5 sm:grid-cols-2">
              {DOCUMENT_REQUEST_OPTIONS.map((d) => (
                <label key={d} className="flex items-center gap-2 text-xs">
                  <Checkbox checked={docs.includes(d)} onCheckedChange={() => toggleDoc(d)} />
                  <span>{d}</span>
                </label>
              ))}
            </div>
            {docs.length > 0 && (
              <div className="text-[11px] text-muted-foreground">{docs.length} document(s) requested</div>
            )}
          </div>
        </div>

        <SheetFooter className="border-t p-4">
          <Button variant="ghost" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button onClick={submit} disabled={sending || !to.trim() || !subject.trim() || !body.trim()} className="gap-1.5">
            <Send className="h-3.5 w-3.5" /> {sending ? "Sending…" : "Send"}
          </Button>
        </SheetFooter>
      </SheetContent>
    </Sheet>
  );
}
