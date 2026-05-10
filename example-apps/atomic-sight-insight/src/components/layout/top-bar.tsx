import { Bell, Moon, Search, Sun } from "lucide-react";
import { SidebarTrigger } from "@/components/ui/sidebar";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useTheme } from "@/hooks/use-theme";
import { RoleSwitcher } from "@/components/auth/role-switcher";

export function TopBar() {
  const { theme, toggle } = useTheme();
  return (
    <header className="flex h-14 items-center gap-3 border-b bg-background px-3">
      <SidebarTrigger />
      <Select defaultValue="acme-sandbox">
        <SelectTrigger className="h-9 w-[180px]">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="acme-sandbox">Acme Corp · Sandbox</SelectItem>
          <SelectItem value="acme-prod">Acme Corp · Production</SelectItem>
          <SelectItem value="lumiere">Lumière Studio</SelectItem>
        </SelectContent>
      </Select>

      <div className="relative ml-2 hidden flex-1 max-w-md md:block">
        <Search className="absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input placeholder="Search transactions, holders, counterparties…" className="h-9 pl-8" />
      </div>

      <div className="ml-auto flex items-center gap-1.5">
        <Button variant="ghost" size="icon" onClick={toggle} aria-label="Toggle theme">
          {theme === "light" ? <Moon className="h-4 w-4" /> : <Sun className="h-4 w-4" />}
        </Button>
        <Button variant="ghost" size="icon" className="relative" aria-label="Notifications">
          <Bell className="h-4 w-4" />
          <span className="absolute right-1.5 top-1.5 h-1.5 w-1.5 rounded-full bg-primary" />
        </Button>
        <RoleSwitcher />
        <Avatar className="h-8 w-8">
          <AvatarFallback className="bg-primary text-primary-foreground text-xs">AO</AvatarFallback>
        </Avatar>
      </div>
    </header>
  );
}
