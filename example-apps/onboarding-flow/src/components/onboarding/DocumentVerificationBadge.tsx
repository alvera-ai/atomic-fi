import { CheckCircle2, AlertTriangle, XCircle } from "lucide-react";
import { cn } from "@/lib/utils";
import { VerificationResult } from "@/types/onboarding";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { FLAG_LABELS } from "@/lib/documentVerification";

interface Props {
  result?: VerificationResult;
  className?: string;
}

const CONFIG = {
  PASS: { icon: CheckCircle2, label: "Verified", className: "text-emerald-600 dark:text-emerald-400" },
  WARN: { icon: AlertTriangle, label: "Needs review", className: "text-amber-600 dark:text-amber-400" },
  FAIL: { icon: XCircle, label: "Rejected", className: "text-destructive" },
};

export function DocumentVerificationBadge({ result, className }: Props) {
  if (!result) return null;
  const cfg = CONFIG[result.status];
  const Icon = cfg.icon;

  return (
    <TooltipProvider delayDuration={150}>
      <Tooltip>
        <TooltipTrigger asChild>
          <div className={cn("flex items-center gap-1.5 text-xs", cfg.className, className)}>
            <Icon className="h-3.5 w-3.5" />
            <span>{cfg.label}</span>
          </div>
        </TooltipTrigger>
        <TooltipContent side="top" className="max-w-xs">
          <p className="font-medium">{cfg.label}</p>
          {result.flags.length > 0 ? (
            <ul className="mt-1 text-xs list-disc pl-4">
              {result.flags.map((f) => (
                <li key={f}>{FLAG_LABELS[f]}</li>
              ))}
            </ul>
          ) : (
            <p className="text-xs mt-1 text-muted-foreground">{result.message}</p>
          )}
        </TooltipContent>
      </Tooltip>
    </TooltipProvider>
  );
}
