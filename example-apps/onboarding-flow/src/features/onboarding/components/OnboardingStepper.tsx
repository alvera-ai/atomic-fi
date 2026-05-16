import { AlertCircle, Check } from "lucide-react";
import { Progress } from "@/components/ui/progress";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { ONBOARDING_STEPS } from "@/features/onboarding/constants";
import { cn } from "@/lib/utils";

interface OnboardingStepperProps {
  currentStep: number;
  completedSteps: number[];
  onStepClick: (stepId: number) => void;
  collapsed?: boolean;
}

export function OnboardingStepper({
  currentStep,
  completedSteps,
  onStepClick,
  collapsed = false,
}: OnboardingStepperProps) {
  const progress = (completedSteps.length / ONBOARDING_STEPS.length) * 100;

  const getStepStatus = (stepId: number) => {
    if (completedSteps.includes(stepId)) return "complete";
    if (stepId === currentStep) return "current";
    return "incomplete";
  };

  return (
    <div className="flex flex-col h-full">
      {/* Progress bar */}
      <div className={cn("px-4 py-3 border-b border-border", collapsed && "px-2")}>
        {!collapsed && (
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-medium text-muted-foreground">Progress</span>
            <span className="text-xs font-semibold text-foreground">{Math.round(progress)}%</span>
          </div>
        )}
        <Progress value={progress} className="h-1.5" />
      </div>

      {/* Steps list */}
      <nav className="flex-1 py-4 px-2 space-y-1 overflow-y-auto">
        {ONBOARDING_STEPS.map((step) => {
          const status = getStepStatus(step.id);
          const isComplete = status === "complete";
          const isCurrent = status === "current";
          const isIncomplete = status === "incomplete";

          const stepContent = (
            <button
              type="button"
              onClick={() => onStepClick(step.id)}
              className={cn(
                "w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors text-left",
                "hover:bg-sidebar-accent hover:text-sidebar-accent-foreground",
                isCurrent && "bg-sidebar-accent text-sidebar-primary",
                isComplete && "text-sidebar-foreground",
                isIncomplete && "text-muted-foreground",
              )}
            >
              {/* Step indicator */}
              <div
                className={cn(
                  "flex items-center justify-center h-6 w-6 rounded-full text-xs font-semibold shrink-0 transition-colors",
                  isComplete && "bg-primary text-primary-foreground",
                  isCurrent && "bg-primary text-primary-foreground",
                  isIncomplete && "bg-muted text-muted-foreground border border-border",
                )}
              >
                {isComplete ? <Check className="h-3.5 w-3.5" /> : step.id}
              </div>

              {/* Step title and warning */}
              {!collapsed && (
                <div className="flex items-center gap-2 flex-1 min-w-0">
                  <span className="truncate">{step.title}</span>
                  {isIncomplete && !isCurrent && (
                    <AlertCircle className="h-3.5 w-3.5 text-amber-500 shrink-0" />
                  )}
                </div>
              )}
            </button>
          );

          if (collapsed) {
            return (
              <Tooltip key={step.id} delayDuration={0}>
                <TooltipTrigger asChild>{stepContent}</TooltipTrigger>
                <TooltipContent side="right" className="font-medium">
                  <div>
                    <p>{step.title}</p>
                    {isIncomplete && !isCurrent && (
                      <p className="text-xs text-amber-500">Incomplete</p>
                    )}
                  </div>
                </TooltipContent>
              </Tooltip>
            );
          }

          return <div key={step.id}>{stepContent}</div>;
        })}
      </nav>
    </div>
  );
}
