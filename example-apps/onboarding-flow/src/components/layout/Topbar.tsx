import { Menu, Search } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { UserMenu } from "./UserMenu";
import { ThemeToggle } from "./ThemeToggle";

interface TopbarProps {
  onMenuClick: () => void;
  showMenuButton: boolean;
}

export function Topbar({ onMenuClick, showMenuButton }: TopbarProps) {
  return (
    <header className="sticky top-0 z-30 flex items-center justify-between h-14 px-4 bg-background border-b border-border">
      {/* Left: Hamburger Menu (mobile) + Search */}
      <div className="flex items-center gap-3 flex-1">
        {showMenuButton && (
          <Button
            variant="ghost"
            size="icon"
            onClick={onMenuClick}
            className="h-9 w-9 lg:hidden"
          >
            <Menu className="h-5 w-5" />
            <span className="sr-only">Toggle menu</span>
          </Button>
        )}
        
        {/* Search Input - Left aligned */}
        <div className="hidden sm:flex max-w-md">
          <div className="relative w-full">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              type="search"
              placeholder="Search..."
              className="w-full pl-10 h-9 bg-muted/50 border-transparent focus:border-input min-w-[280px]"
            />
          </div>
        </div>
      </div>

      {/* Right: Theme Toggle + User Menu */}
      <div className="flex items-center gap-2">
        <ThemeToggle />
        <UserMenu />
      </div>
    </header>
  );
}
