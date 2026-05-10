import { Card } from "@/components/ui/card";
import { Sparkles } from "lucide-react";

export function PlaceholderScreen({ title, intent }: { title: string; intent: string }) {
  return (
    <div className="p-6">
      <div className="mb-4">
        <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
      </div>
      <Card className="flex flex-col items-center justify-center gap-3 p-12 text-center">
        <div className="flex h-12 w-12 items-center justify-center rounded-full bg-primary/10 text-primary">
          <Sparkles className="h-5 w-5" />
        </div>
        <div className="text-base font-medium">Coming next</div>
        <p className="max-w-md text-sm text-muted-foreground">{intent}</p>
      </Card>
    </div>
  );
}
