import { CheckCircle } from "lucide-react";

interface AutosaveIndicatorProps {
  lastSaved: Date | null;
}

export function AutosaveIndicator({ lastSaved }: AutosaveIndicatorProps) {
  if (!lastSaved) return null;

  const formatTime = (date: Date) => {
    return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  };

  return (
    <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
      <CheckCircle className="h-3.5 w-3.5 text-green-500" />
      <span>Saved at {formatTime(lastSaved)}</span>
    </div>
  );
}
