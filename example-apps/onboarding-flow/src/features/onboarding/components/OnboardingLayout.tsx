import { ChevronLeft, ChevronRight, HelpCircle } from "lucide-react";
import { useEffect, useState } from "react";
import { Outlet, useLocation, useNavigate, useParams } from "react-router-dom";
import { ThemeToggle } from "@/components/layout/ThemeToggle";
import { UserMenu } from "@/components/layout/UserMenu";
import { Button } from "@/components/ui/button";
import { ONBOARDING_STEPS } from "@/features/onboarding/constants";
import { useApplication } from "@/features/onboarding/useApplication";
import { cn } from "@/lib/utils";
import { AutosaveIndicator } from "./AutosaveIndicator";
import { OnboardingActionBar } from "./OnboardingActionBar";
import { OnboardingStepper } from "./OnboardingStepper";

export function OnboardingLayout() {
  const { applicationId } = useParams<{ applicationId: string }>();
  const navigate = useNavigate();
  const location = useLocation();
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);

  const { application, loading, lastSaved, setCurrentStep, updateApplication } =
    useApplication(applicationId);

  // Determine current step from URL
  const currentPath = location.pathname.split("/").pop() || "documents";
  const currentStepDef = ONBOARDING_STEPS.find((s) => s.path === currentPath);
  const currentStepId = currentStepDef?.id || 1;

  // Update current step when URL changes
  useEffect(() => {
    if (application && currentStepId !== application.current_step) {
      setCurrentStep(currentStepId);
    }
  }, [currentStepId, application, setCurrentStep]);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-screen bg-background">
        <div className="text-muted-foreground">Loading application...</div>
      </div>
    );
  }

  if (!application) {
    return (
      <div className="flex flex-col items-center justify-center h-screen bg-background gap-4">
        <div className="text-muted-foreground">Application not found</div>
        <Button onClick={() => navigate("/start")}>Start New Application</Button>
      </div>
    );
  }

  const handleStepClick = (stepId: number) => {
    const step = ONBOARDING_STEPS.find((s) => s.id === stepId);
    if (step) {
      navigate(`/onboarding/${applicationId}/${step.path}`);
    }
  };

  const handleBack = () => {
    if (currentStepId > 1) {
      const prevStep = ONBOARDING_STEPS.find((s) => s.id === currentStepId - 1);
      if (prevStep) {
        navigate(`/onboarding/${applicationId}/${prevStep.path}`);
      }
    }
  };

  const handleContinue = () => {
    if (currentStepId < ONBOARDING_STEPS.length) {
      const nextStep = ONBOARDING_STEPS.find((s) => s.id === currentStepId + 1);
      if (nextStep) {
        navigate(`/onboarding/${applicationId}/${nextStep.path}`);
      }
    }
  };

  const handleSaveExit = () => {
    navigate("/start");
  };

  const isLastStep = currentStepId === ONBOARDING_STEPS.length;

  return (
    <div className="flex h-screen w-full bg-background overflow-hidden">
      {/* Left Sidebar with Stepper */}
      <aside
        className={cn(
          "relative flex flex-col h-full bg-sidebar border-r border-sidebar-border transition-all duration-300 ease-in-out",
          sidebarCollapsed ? "w-16" : "w-64",
        )}
      >
        {/* Sidebar Header */}
        <div
          className={cn(
            "flex items-center h-14 border-b border-sidebar-border px-3 shrink-0",
            sidebarCollapsed ? "justify-center" : "justify-between",
          )}
        >
          {!sidebarCollapsed && (
            <span className="font-semibold text-sidebar-foreground text-sm">Onboarding</span>
          )}
          <Button
            variant="ghost"
            size="icon"
            onClick={() => setSidebarCollapsed((prev) => !prev)}
            className="h-8 w-8 text-sidebar-foreground hover:bg-sidebar-accent"
          >
            {sidebarCollapsed ? (
              <ChevronRight className="h-4 w-4" />
            ) : (
              <ChevronLeft className="h-4 w-4" />
            )}
          </Button>
        </div>

        {/* Stepper */}
        <OnboardingStepper
          currentStep={currentStepId}
          completedSteps={application.completed_steps}
          onStepClick={handleStepClick}
          collapsed={sidebarCollapsed}
        />
      </aside>

      {/* Main Content */}
      <div className="flex flex-1 flex-col min-w-0 h-screen overflow-hidden">
        {/* Top Header */}
        <header className="sticky top-0 z-30 flex items-center justify-between h-14 px-6 bg-background border-b border-border shrink-0">
          <div className="flex items-center gap-4">
            <span className="font-semibold text-foreground">Dubai → US</span>
            <AutosaveIndicator lastSaved={lastSaved} />
          </div>

          <div className="flex items-center gap-2">
            <Button variant="ghost" size="sm" className="gap-2 text-muted-foreground">
              <HelpCircle className="h-4 w-4" />
              Help
            </Button>
            <ThemeToggle />
            <UserMenu />
          </div>
        </header>

        {/* Step Content */}
        <main className="flex-1 overflow-auto">
          <div className="max-w-4xl mx-auto px-6 py-8">
            <Outlet context={{ application, applicationId, updateApplication }} />
          </div>
        </main>

        {/* Bottom Action Bar */}
        <OnboardingActionBar
          onBack={handleBack}
          onSaveExit={handleSaveExit}
          onContinue={handleContinue}
          showBack={currentStepId > 1}
          showContinue={!isLastStep}
          continueLabel={isLastStep ? "Submit" : "Continue"}
        />
      </div>
    </div>
  );
}
