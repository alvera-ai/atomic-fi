import { ReactNode } from "react";
import { X, Pencil } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
} from "@/components/ui/sheet";

interface DetailSlideOverProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  headerContent?: ReactNode;
  children: ReactNode;
  onEdit?: () => void;
}

export function DetailSlideOver({
  open,
  onOpenChange,
  title,
  headerContent,
  children,
  onEdit,
}: DetailSlideOverProps) {
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-full sm:max-w-md p-0 flex flex-col gap-0 [&>button]:hidden">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-border">
          <h2 className="text-base font-medium text-foreground">{title}</h2>
          <Button
            variant="ghost"
            size="icon"
            className="h-8 w-8 text-muted-foreground"
            onClick={() => onOpenChange(false)}
          >
            <X className="h-4 w-4" />
          </Button>
        </div>

        {/* Colored Header Section */}
        {headerContent && (
          <div className="bg-muted/50 px-5 py-5 border-b border-border">
            {headerContent}
          </div>
        )}

        {/* Scrollable Content */}
        <div className="flex-1 overflow-y-auto px-5 py-5">
          {children}
        </div>

        {/* Footer with Edit Button */}
        <div className="flex items-center justify-end px-5 py-3 border-t border-border bg-background">
          <Button 
            variant="secondary" 
            onClick={onEdit} 
            className="rounded-full px-4 h-9 text-sm font-medium gap-2"
          >
            <Pencil className="h-4 w-4" />
            Edit
          </Button>
        </div>
      </SheetContent>
    </Sheet>
  );
}

// Reusable field component for the slideover (read-only display)
interface DetailFieldProps {
  label: string;
  children: ReactNode;
  className?: string;
}

export function DetailField({ label, children, className = "" }: DetailFieldProps) {
  return (
    <div className={`space-y-1 ${className}`}>
      <label className="text-sm text-muted-foreground">{label}</label>
      <div className="text-sm font-medium text-foreground">{children}</div>
    </div>
  );
}
