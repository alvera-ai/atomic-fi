import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Navigate, Route, Routes, useLocation } from "react-router-dom";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import { AppLayout } from "@/components/layout/app-layout";
import TransactionsPage from "./pages/TransactionsPage";
import DashboardPage from "./pages/DashboardPage";
import WorkQueuePage from "./pages/WorkQueuePage";
import CustomersPage from "./pages/CustomersPage";
import RulesPage from "./pages/RulesPage";
import IntegrationsPage from "./pages/IntegrationsPage";
import HealthPage from "./pages/HealthPage";
import NotFound from "./pages/NotFound";
import { RouteGuard } from "@/components/auth/route-guard";
import { useAuth } from "@/contexts/auth-context";
import { ROLE_DEFAULT_ROUTE } from "@/lib/nav-access";

function RoleHome() {
  const { user } = useAuth();
  return <Navigate to={ROLE_DEFAULT_ROUTE[user.role]} replace />;
}

function RedirectWithSearch({ to }: { to: string }) {
  const { search } = useLocation();
  // If `to` already has a query, append; else set
  const sep = to.includes("?") ? "&" : "?";
  const target = search ? `${to}${sep}${search.slice(1)}` : to;
  return <Navigate to={target} replace />;
}

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <BrowserRouter>
        <Routes>
          <Route element={<AppLayout />}>
            <Route element={<RouteGuard />}>
              <Route path="/" element={<RoleHome />} />
              <Route path="/dashboard" element={<DashboardPage />} />
              <Route path="/queue" element={<WorkQueuePage />} />
              <Route path="/customers" element={<CustomersPage />} />
              <Route path="/transactions" element={<TransactionsPage />} />
              <Route path="/rules" element={<RulesPage />} />
              {/* Legacy redirects */}
              <Route path="/cases" element={<Navigate to="/queue" replace />} />
              <Route path="/review" element={<Navigate to="/queue?tab=sanctions" replace />} />
              <Route path="/onboarding" element={<Navigate to="/customers" replace />} />
              <Route path="/talk-to-data" element={<RedirectWithSearch to="/rules?tab=intelligence" />} />
              <Route path="/recommendations" element={<RedirectWithSearch to="/rules?tab=recommendations" />} />
              <Route path="/audit" element={<RedirectWithSearch to="/rules?tab=audit" />} />
              <Route path="/integrations" element={<IntegrationsPage />} />
              <Route path="/health" element={<HealthPage />} />
            </Route>
          </Route>
          <Route path="*" element={<NotFound />} />
        </Routes>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;
