import { useEffect, useState } from "react";
import { Outlet } from "react-router-dom";
import { Sheet, SheetContent } from "@/components/ui/sheet";
import { useIsMobile } from "@/hooks/use-mobile";
import { Sidebar } from "./Sidebar";
import { Topbar } from "./Topbar";

export function AppLayout() {
  const isMobile = useIsMobile();
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  // Close mobile menu when switching to desktop
  useEffect(() => {
    if (!isMobile) {
      setMobileMenuOpen(false);
    }
  }, [isMobile]);

  const handleSidebarToggle = () => {
    setSidebarCollapsed((prev) => !prev);
  };

  const handleMobileMenuToggle = () => {
    setMobileMenuOpen((prev) => !prev);
  };

  const handleMobileItemClick = () => {
    setMobileMenuOpen(false);
  };

  return (
    <div className="flex h-screen w-full bg-background overflow-hidden">
      {/* Desktop/Tablet Sidebar - Full Height */}
      {!isMobile && <Sidebar collapsed={sidebarCollapsed} onToggle={handleSidebarToggle} />}

      {/* Mobile Sidebar Drawer */}
      {isMobile && (
        <Sheet open={mobileMenuOpen} onOpenChange={setMobileMenuOpen}>
          <SheetContent side="left" className="p-0 w-60">
            {/* biome-ignore lint/suspicious/noEmptyBlockStatements: noop — mobile drawer sidebar has no toggle */}
            <Sidebar collapsed={false} onToggle={() => {}} onItemClick={handleMobileItemClick} />
          </SheetContent>
        </Sheet>
      )}

      {/* Main Content Area */}
      <div className="flex flex-1 flex-col min-w-0 h-screen overflow-hidden">
        <Topbar onMenuClick={handleMobileMenuToggle} showMenuButton={isMobile} />
        <main className="flex-1 px-10 py-8 overflow-auto bg-background">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
