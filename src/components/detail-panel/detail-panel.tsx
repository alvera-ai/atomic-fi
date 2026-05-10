import { useState, type ReactNode } from "react";
import type { LucideIcon } from "lucide-react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";
import { StatusPill } from "@/components/status-pill";
import { usePermission } from "@/hooks/use-permission";
import { cn } from "@/lib/utils";

export interface DetailPanelTab {
  id: string;
  label: string;
  badge?: ReactNode;
  render: () => ReactNode;
}

export interface DetailPanelAction {
  id: string;
  label: string;
  icon: LucideIcon;
  permission?: string;
  onClick: () => void;
  tone?: "primary" | "secondary";
}

interface DetailPanelProps {
  title: string;
  statusValue?: string | null;
  subtitle: ReactNode;
  actions?: DetailPanelAction[];
  tabs: DetailPanelTab[];
  defaultTab?: string;
  activeTab?: string;
  onTabChange?: (id: string) => void;
  banner?: ReactNode;
}

export function DetailPanel({
  title,
  statusValue,
  subtitle,
  actions = [],
  tabs,
  defaultTab,
  activeTab,
  onTabChange,
  banner,
}: DetailPanelProps) {
  const [internal, setInternal] = useState(defaultTab ?? tabs[0]?.id);
  const current = activeTab ?? internal;
  const setCurrent = (v: string) => {
    setInternal(v);
    onTabChange?.(v);
  };

  return (
    <div className="flex h-full flex-col">
      <div className="space-y-2 border-b p-4">
        <div className="flex items-start gap-2">
          <h2 className="min-w-0 flex-1 truncate text-lg font-semibold leading-tight">{title}</h2>
          {statusValue && <StatusPill value={statusValue} />}
        </div>
        <div className="text-xs text-muted-foreground">{subtitle}</div>
        {actions.length > 0 && (
          <div className="flex flex-wrap items-center gap-1.5 pt-1">
            {actions.map((a) => (
              <ActionButton key={a.id} action={a} />
            ))}
          </div>
        )}
        {banner}
      </div>

      <Tabs value={current} onValueChange={setCurrent} className="flex min-h-0 flex-1 flex-col">
        <div className="border-b px-2">
          <TabsList className="h-auto gap-1 rounded-none bg-transparent p-0">
            {tabs.map((t) => (
              <TabsTrigger
                key={t.id}
                value={t.id}
                className={cn(
                  "relative rounded-none border-b-2 border-transparent bg-transparent px-3 py-2 text-xs font-medium text-muted-foreground shadow-none",
                  "data-[state=active]:border-warning data-[state=active]:bg-transparent data-[state=active]:text-foreground data-[state=active]:shadow-none",
                )}
              >
                {t.label}
                {t.badge}
              </TabsTrigger>
            ))}
          </TabsList>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto p-4">
          {tabs.map((t) => (
            <TabsContent key={t.id} value={t.id} className="m-0 space-y-3">
              {t.render()}
            </TabsContent>
          ))}
        </div>
      </Tabs>
    </div>
  );
}

function ActionButton({ action }: { action: DetailPanelAction }) {
  const allowedByPerm = usePermission(action.permission ?? "__always__");
  const allowed = action.permission ? allowedByPerm : true;
  if (!allowed) return null;
  const Icon = action.icon;
  const orange = action.tone !== "secondary";
  return (
    <Button
      size="sm"
      variant="outline"
      onClick={action.onClick}
      className={cn(
        "h-8 gap-1.5",
        orange && "border-warning/50 text-warning-foreground hover:bg-warning/10 hover:text-warning-foreground",
      )}
    >
      <Icon className="h-3.5 w-3.5" />
      {action.label}
    </Button>
  );
}

export function SectionHeading({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div
      className={cn(
        "text-[11px] font-semibold uppercase tracking-wider text-muted-foreground",
        className,
      )}
    >
      {children}
    </div>
  );
}

export function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="grid grid-cols-[140px_1fr] items-start gap-2 border-b border-border/50 py-1.5 last:border-b-0">
      <div className="text-xs text-muted-foreground">{label}</div>
      <div className="break-all text-xs font-medium text-foreground">{children}</div>
    </div>
  );
}

export function PanelSection({
  title,
  action,
  children,
  className,
}: {
  title?: ReactNode;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("rounded-md border bg-card", className)}>
      {(title || action) && (
        <div className="flex items-center gap-2 border-b px-3 py-2">
          {title && <SectionHeading>{title}</SectionHeading>}
          {action && <div className="ml-auto">{action}</div>}
        </div>
      )}
      <div className="p-3">{children}</div>
    </div>
  );
}
