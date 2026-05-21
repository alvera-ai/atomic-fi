import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { AppLayout } from "@/components/layout";
import { OnboardingLayout } from "@/features/onboarding/components/OnboardingLayout";
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
} from "@/features/onboarding/components/steps";
import StartPage from "@/features/onboarding/pages/Start";
import NotFound from "@/features/ops/pages/NotFound";
import OpsDetailPage from "@/features/ops/pages/OpsDetail";
import OpsListPage from "@/features/ops/pages/OpsList";
import StatusPage from "@/features/ops/pages/Status";

export function AppRoutes() {
  return (
    // basename = the Vite `base` ("/demo/onboarding-flow/" in this repo,
    // "/" elsewhere). Phoenix serves the app under that prefix via
    // Plug.Static, so the router must strip it before matching routes.
    <BrowserRouter basename={import.meta.env.BASE_URL}>
      <Routes>
        <Route path="/" element={<Navigate to="/start" replace />} />

        <Route path="/start" element={<StartPage />} />

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

        <Route path="/status/:applicationId" element={<StatusPage />} />

        <Route element={<AppLayout />}>
          <Route path="/ops" element={<OpsListPage />} />
          <Route path="/ops/:applicationId" element={<OpsDetailPage />} />
        </Route>

        <Route path="*" element={<NotFound />} />
      </Routes>
    </BrowserRouter>
  );
}
