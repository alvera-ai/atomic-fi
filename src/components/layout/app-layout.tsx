import { Outlet } from "react-router-dom";
import { SidebarProvider } from "@/components/ui/sidebar";
import { AppSidebar } from "@/components/layout/app-sidebar";
import { TopBar } from "@/components/layout/top-bar";
import { CopilotFab } from "@/components/layout/copilot-fab";
import { CopilotDrawer } from "@/components/copilot/copilot-drawer";
import { CopilotProvider } from "@/contexts/copilot-context";
import { AuthProvider } from "@/contexts/auth-context";

export function AppLayout() {
  return (
    <AuthProvider>
    <CopilotProvider>
      <SidebarProvider>
        <div className="flex min-h-screen w-full bg-muted/30">
          <AppSidebar />
          <div className="flex min-w-0 flex-1 flex-col">
            <TopBar />
            <main className="min-w-0 flex-1 overflow-hidden">
              <Outlet />
            </main>
          </div>
          <CopilotFab />
          <CopilotDrawer />
        </div>
      </SidebarProvider>
    </CopilotProvider>
    </AuthProvider>
  );
}
