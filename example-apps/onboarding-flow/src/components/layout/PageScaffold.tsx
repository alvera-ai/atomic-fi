import { ReactNode } from "react";
import { Button } from "@/components/ui/button";
import { Plus } from "lucide-react";

interface PageScaffoldProps {
  title: string;
  description?: string;
  actionLabel?: string;
  onAction?: () => void;
  children?: ReactNode;
}

export function PageScaffold({ 
  title, 
  description, 
  actionLabel,
  onAction,
  children 
}: PageScaffoldProps) {
  return (
    <div className="max-w-6xl">
      {/* Page Header - Mercury style */}
      <div className="flex items-start justify-between mb-8">
        <div>
          <h1 className="text-[28px] font-semibold tracking-tight text-foreground">
            {title}
          </h1>
          {description && (
            <p className="text-muted-foreground mt-1 text-sm">{description}</p>
          )}
        </div>
        {actionLabel && (
          <Button 
            variant="outline" 
            onClick={onAction}
            className="rounded-full px-4 h-9 text-sm font-medium"
          >
            <Plus className="h-4 w-4 mr-1.5" />
            {actionLabel}
          </Button>
        )}
      </div>

      {/* Content Area */}
      <div>
        {children || (
          <p className="text-muted-foreground text-sm">No content yet</p>
        )}
      </div>
    </div>
  );
}
