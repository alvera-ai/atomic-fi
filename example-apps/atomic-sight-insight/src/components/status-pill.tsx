import { cn } from "@/lib/utils";

const STATUS_CLASSES: Record<string, string> = {
  settled: "bg-success/15 text-success border-success/20",
  accepted: "bg-info/15 text-info border-info/20",
  pending: "bg-warning/20 text-warning-foreground border-warning/30",
  rejected: "bg-destructive/15 text-destructive border-destructive/20",
  cancelled: "bg-destructive/15 text-destructive border-destructive/20",
  reversed: "bg-muted text-muted-foreground border-border",

  // KYC / risk
  approved: "bg-success/15 text-success border-success/20",
  in_progress: "bg-info/15 text-info border-info/20",
  not_started: "bg-muted text-muted-foreground border-border",
  on_hold: "bg-warning/20 text-warning-foreground border-warning/30",

  low: "bg-success/15 text-success border-success/20",
  medium: "bg-warning/20 text-warning-foreground border-warning/30",
  high: "bg-orange-500/15 text-orange-600 border-orange-500/30 dark:text-orange-400",
  critical: "bg-destructive/25 text-destructive border-destructive/30",
  prohibited: "bg-destructive/25 text-destructive border-destructive/30",

  // Counterparty
  active: "bg-success/15 text-success border-success/20",
  blocked: "bg-destructive/15 text-destructive border-destructive/20",
  under_review: "bg-warning/20 text-warning-foreground border-warning/30",
  suspended: "bg-destructive/15 text-destructive border-destructive/20",

  // Screening
  clear: "bg-success/15 text-success border-success/20",
  potential_match: "bg-warning/20 text-warning-foreground border-warning/30",
  match: "bg-destructive/15 text-destructive border-destructive/20",
  review: "bg-info/15 text-info border-info/20",

  // KYC requirement
  submitted: "bg-info/15 text-info border-info/20",
  waived: "bg-muted text-muted-foreground border-border",

  // Rule lifecycle
  live: "bg-success/15 text-success border-success/20",
  sandbox: "bg-info/15 text-info border-info/20",
  archived: "bg-muted text-muted-foreground border-border",

  // Rule severity (high, medium, low, critical already defined above)

  // Rule action
  flag: "bg-warning/20 text-warning-foreground border-warning/30",
  block: "bg-destructive/15 text-destructive border-destructive/20",
};

export function StatusPill({ value, className }: { value: string | null | undefined; className?: string }) {
  const v = value ?? "—";
  const tone = STATUS_CLASSES[v] ?? "bg-muted text-muted-foreground border-border";
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full border px-2 py-0.5 text-[11px] font-medium capitalize",
        tone,
        className,
      )}
    >
      {v.replace(/_/g, " ")}
    </span>
  );
}
