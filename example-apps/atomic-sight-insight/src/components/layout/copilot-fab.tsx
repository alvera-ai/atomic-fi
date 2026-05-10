import { Sparkles } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useCopilot } from "@/contexts/copilot-context";

export function CopilotFab() {
  const { openDrawer } = useCopilot();
  return (
    <Button
      onClick={openDrawer}
      className="fixed bottom-5 right-5 z-40 h-12 gap-2 rounded-full px-5 shadow-lg shadow-primary/30"
      aria-label="Open Copilot"
    >
      <Sparkles className="h-4 w-4" />
      Copilot
    </Button>
  );
}
