import { useState } from "react";
import { format } from "date-fns";
import { CalendarIcon, Flag } from "lucide-react";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { Calendar } from "@/components/ui/calendar";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { createCase, type CasePriority, type CaseType } from "@/api/cases";
import { useAuditLogger } from "@/hooks/use-audit-logger";

type FlagType = Extract<CaseType, "rule_breach" | "sanctions_match" | "transaction_flag">;

const FLAG_TYPES: FlagType[] = ["rule_breach", "sanctions_match", "transaction_flag"];
const PRIORITIES: CasePriority[] = ["critical", "high", "medium", "low"];
const FLAG_ASSIGNEES = ["Ana Martins", "James Osei", "Priya Nair"];

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  transactionId: string;
  defaultTitle?: string;
  onCreated?: () => void;
}

export function CreateFlagDialog({ open, onOpenChange, transactionId, defaultTitle, onCreated }: Props) {
  const [type, setType] = useState<FlagType>("transaction_flag");
  const [priority, setPriority] = useState<CasePriority>("medium");
  const [description, setDescription] = useState("");
  const [assignee, setAssignee] = useState<string>("Unassigned");
  const [due, setDue] = useState<Date | undefined>(() => new Date(Date.now() + 3 * 86_400_000));
  const logAudit = useAuditLogger();

  const reset = () => {
    setType("transaction_flag");
    setPriority("medium");
    setDescription("");
    setAssignee("Unassigned");
    setDue(new Date(Date.now() + 3 * 86_400_000));
  };

  const submit = async () => {
    if (!description.trim() || !due) return;
    const title = defaultTitle ?? `Flagged transaction ${transactionId.slice(0, 8)}`;
    const created = await createCase({
      type,
      status: "open",
      priority,
      title,
      description: description.trim(),
      source_id: transactionId,
      source_type: "transaction",
      assigned_to: assignee,
      due_date: due.toISOString(),
    });
    logAudit({
      action_type: "case.created",
      resource_type: "case",
      resource_id: created.id,
      description: `Created case '${title}'`,
      metadata: { type, priority },
    });
    toast.success("Flag created", { description: `Case opened · ${type.replace(/_/g, " ")}` });
    reset();
    onOpenChange(false);
    onCreated?.();
  };

  return (
    <Dialog open={open} onOpenChange={(v) => { if (!v) reset(); onOpenChange(v); }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Flag className="h-4 w-4" /> Create flag
          </DialogTitle>
          <DialogDescription>Open a case linked to this transaction.</DialogDescription>
        </DialogHeader>
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-2">
            <div className="space-y-1.5">
              <Label className="text-xs">Flag type</Label>
              <Select value={type} onValueChange={(v) => setType(v as FlagType)}>
                <SelectTrigger className="h-9"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {FLAG_TYPES.map((t) => <SelectItem key={t} value={t}>{t.replace(/_/g, " ")}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs">Priority</Label>
              <Select value={priority} onValueChange={(v) => setPriority(v as CasePriority)}>
                <SelectTrigger className="h-9"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {PRIORITIES.map((p) => <SelectItem key={p} value={p}>{p}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="space-y-1.5">
            <Label className="text-xs">Description</Label>
            <Textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Describe why this transaction is being flagged…"
              rows={3}
            />
          </div>
          <div className="grid grid-cols-2 gap-2">
            <div className="space-y-1.5">
              <Label className="text-xs">Assign to</Label>
              <Select value={assignee} onValueChange={setAssignee}>
                <SelectTrigger className="h-9"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Unassigned">Unassigned</SelectItem>
                  {FLAG_ASSIGNEES.map((a) => <SelectItem key={a} value={a}>{a}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs">Due date</Label>
              <Popover>
                <PopoverTrigger asChild>
                  <Button
                    variant="outline"
                    className={cn("h-9 w-full justify-start text-left font-normal", !due && "text-muted-foreground")}
                  >
                    <CalendarIcon className="mr-1.5 h-3.5 w-3.5" />
                    {due ? format(due, "yyyy-MM-dd") : "Pick a date"}
                  </Button>
                </PopoverTrigger>
                <PopoverContent className="w-auto p-0" align="start">
                  <Calendar
                    mode="single"
                    selected={due}
                    onSelect={setDue}
                    initialFocus
                    className={cn("p-3 pointer-events-auto")}
                  />
                </PopoverContent>
              </Popover>
            </div>
          </div>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button onClick={submit} disabled={!description.trim() || !due}>Create flag</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
