import { Building2, ChevronDown, Settings } from "lucide-react";
import { useState } from "react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";

const brands = [
  { id: "1", name: "Prime Family Medicine" },
  { id: "2", name: "Prime Ortho" },
  { id: "3", name: "Sunrise Cardiology" },
];

interface BrandSwitcherProps {
  collapsed: boolean;
}

export function BrandSwitcher({ collapsed }: BrandSwitcherProps) {
  const [selectedBrand, setSelectedBrand] = useState(brands[0]);

  const trigger = (
    <DropdownMenuTrigger asChild>
      <Button
        variant="ghost"
        className={cn(
          "w-full justify-start gap-2 h-10 px-3 text-sidebar-foreground hover:bg-sidebar-accent",
          collapsed && "justify-center px-0"
        )}
      >
        <Building2 className="h-5 w-5 shrink-0" />
        {!collapsed && (
          <>
            <span className="truncate text-sm font-medium flex-1 text-left">
              {selectedBrand.name}
            </span>
            <ChevronDown className="h-4 w-4 shrink-0 opacity-50" />
          </>
        )}
      </Button>
    </DropdownMenuTrigger>
  );

  return (
    <DropdownMenu>
      {collapsed ? (
        <Tooltip delayDuration={0}>
          <TooltipTrigger asChild>{trigger}</TooltipTrigger>
          <TooltipContent side="right" className="font-medium">
            {selectedBrand.name}
          </TooltipContent>
        </Tooltip>
      ) : (
        trigger
      )}
      <DropdownMenuContent
        align={collapsed ? "center" : "start"}
        side={collapsed ? "right" : "top"}
        className="w-56"
      >
        {brands.map((brand) => (
          <DropdownMenuItem
            key={brand.id}
            onClick={() => setSelectedBrand(brand)}
            className={cn(
              "cursor-pointer",
              selectedBrand.id === brand.id && "bg-accent"
            )}
          >
            <Building2 className="mr-2 h-4 w-4" />
            <span className="truncate">{brand.name}</span>
          </DropdownMenuItem>
        ))}
        <DropdownMenuSeparator />
        <DropdownMenuItem className="cursor-pointer">
          <Settings className="mr-2 h-4 w-4" />
          Manage brands
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
