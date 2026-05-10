import { useEffect, useState } from "react";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { toast as sonnerToast } from "sonner";

export const TEAM_MEMBERS = ["Unassigned", "Ana Martins", "James Osei", "Priya Nair", "Alex Officer"];

interface AssignDialogProps {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  current?: string;
  resourceLabel: string;
  onAssign: (assignee: string) => void;
}

export function AssignDialog({ open, onOpenChange, current, resourceLabel, onAssign }: AssignDialogProps) {
  const [value, setValue] = useState(current ?? "Unassigned");
  useEffect(() => { if (open) setValue(current ?? "Unassigned"); }, [open, current]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-sm">
        <DialogHeader>
          <DialogTitle>Assign {resourceLabel}</DialogTitle>
        </DialogHeader>
        <div className="space-y-2">
          <Label className="text-xs">Assignee</Label>
          <Select value={value} onValueChange={setValue}>
            <SelectTrigger className="h-9"><SelectValue /></SelectTrigger>
            <SelectContent>
              {TEAM_MEMBERS.map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>Cancel</Button>
          <Button onClick={() => { onAssign(value); sonnerToast.success("Assigned", { description: value }); onOpenChange(false); }}>
            Assign
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
