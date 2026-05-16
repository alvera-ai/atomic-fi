import { ChevronLeft, ChevronRight, ClipboardList, Users } from "lucide-react";
import { NavLink, useLocation } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";
import { BrandSwitcher } from "./BrandSwitcher";

interface SidebarProps {
  collapsed: boolean;
  onToggle: () => void;
  onItemClick?: () => void;
}

const menuItems = [
  { title: "Onboarding flow", path: "/start", icon: ClipboardList },
  { title: "Ops Dashboard", path: "/ops", icon: Users },
];

export function Sidebar({ collapsed, onToggle, onItemClick }: SidebarProps) {
  const location = useLocation();

  return (
    <aside
      className={cn(
        "relative flex flex-col h-full bg-sidebar border-r border-sidebar-border transition-all duration-300 ease-in-out",
        collapsed ? "w-16" : "w-60",
      )}
    >
      {/* Sidebar Header with Toggle */}
      <div
        className={cn(
          "flex items-center h-14 border-b border-sidebar-border px-3 shrink-0",
          collapsed ? "justify-center" : "justify-between",
        )}
      >
        {!collapsed && (
          <span className="font-semibold text-sidebar-foreground text-sm">Compliance</span>
        )}
        <Button
          variant="ghost"
          size="icon"
          onClick={onToggle}
          className="h-8 w-8 text-sidebar-foreground hover:bg-sidebar-accent"
        >
          {collapsed ? <ChevronRight className="h-4 w-4" /> : <ChevronLeft className="h-4 w-4" />}
        </Button>
      </div>

      {/* Navigation Menu */}
      <nav className="flex-1 py-4 px-2 space-y-1 overflow-y-auto pb-16">
        {menuItems.map((item) => {
          const isActive =
            location.pathname === item.path ||
            (item.path === "/ops" && location.pathname.startsWith("/ops"));
          const Icon = item.icon;

          const linkContent = (
            <NavLink
              to={item.path}
              onClick={onItemClick}
              className={cn(
                "flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors",
                "hover:bg-sidebar-accent hover:text-sidebar-accent-foreground",
                isActive ? "bg-sidebar-accent text-sidebar-primary" : "text-sidebar-foreground",
              )}
            >
              <Icon className={cn("h-5 w-5 shrink-0", isActive && "text-sidebar-primary")} />
              {!collapsed && <span>{item.title}</span>}
            </NavLink>
          );

          if (collapsed) {
            return (
              <Tooltip key={item.path} delayDuration={0}>
                <TooltipTrigger asChild>{linkContent}</TooltipTrigger>
                <TooltipContent side="right" className="font-medium">
                  {item.title}
                </TooltipContent>
              </Tooltip>
            );
          }

          return <div key={item.path}>{linkContent}</div>;
        })}
      </nav>

      {/* Brand Switcher Footer - Sticky at bottom */}
      <div className="absolute bottom-0 left-0 right-0 border-t border-sidebar-border p-2 bg-sidebar">
        <BrandSwitcher collapsed={collapsed} />
      </div>
    </aside>
  );
}
