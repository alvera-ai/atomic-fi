import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ThemeProvider } from "next-themes";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { AppLayout } from "@/components/layout";
import { OnboardingLayout } from "@/components/onboarding/OnboardingLayout";
import {
  StepActivity,
  StepAddresses,
  StepContacts,
  StepDirectors,
  StepDocuments,
  StepIdentity,
  StepOwnership,
  StepReview,
  StepTransfers,
  StepUBOs,
} from "@/components/onboarding/steps";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { Toaster } from "@/components/ui/toaster";
import { TooltipProvider } from "@/components/ui/tooltip";
import NotFound from "./pages/NotFound";
import OpsDetailPage from "./pages/OpsDetail";
import OpsListPage from "./pages/OpsList";
import StartPage from "./pages/Start";
import StatusPage from "./pages/Status";

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <ThemeProvider attribute="class" defaultTheme="system" enableSystem>
      <TooltipProvider>
        <Toaster />
        <Sonner />
        <BrowserRouter>
          <Routes>
            {/* Redirect root to start */}
            <Route path="/" element={<Navigate to="/start" replace />} />

            {/* Start page - choose onboarding method */}
            <Route path="/start" element={<StartPage />} />

            {/* Onboarding flow with stepper */}
            <Route path="/onboarding/:applicationId" element={<OnboardingLayout />}>
              <Route index element={<Navigate to="documents" replace />} />
              <Route path="documents" element={<StepDocuments />} />
              <Route path="identity" element={<StepIdentity />} />
              <Route path="addresses" element={<StepAddresses />} />
              <Route path="contacts" element={<StepContacts />} />
              <Route path="activity" element={<StepActivity />} />
              <Route path="transfers" element={<StepTransfers />} />
              <Route path="ownership" element={<StepOwnership />} />
              <Route path="directors" element={<StepDirectors />} />
              <Route path="ubos" element={<StepUBOs />} />
              <Route path="review" element={<StepReview />} />
            </Route>

            {/* Customer status page */}
            <Route path="/status/:applicationId" element={<StatusPage />} />

            {/* Ops dashboard */}
            <Route element={<AppLayout />}>
              <Route path="/ops" element={<OpsListPage />} />
              <Route path="/ops/:applicationId" element={<OpsDetailPage />} />
            </Route>

            {/* Catch-all */}
            <Route path="*" element={<NotFound />} />
          </Routes>
        </BrowserRouter>
      </TooltipProvider>
    </ThemeProvider>
  </QueryClientProvider>
);

export default App;
