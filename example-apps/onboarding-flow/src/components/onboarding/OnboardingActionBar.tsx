import { ReactNode } from "react";
import { ChevronLeft, Save, ArrowRight } from "lucide-react";
import { Button } from "@/components/ui/button";

interface OnboardingActionBarProps {
  onBack: () => void;
  onSaveExit: () => void;
  onContinue: () => void;
  showBack?: boolean;
  showContinue?: boolean;
  continueLabel?: string;
  continueDisabled?: boolean;
}

export function OnboardingActionBar({
  onBack,
  onSaveExit,
  onContinue,
  showBack = true,
  showContinue = true,
  continueLabel = "Continue",
  continueDisabled = false,
}: OnboardingActionBarProps) {
  return (
    <div className="sticky bottom-0 left-0 right-0 bg-background border-t border-border px-6 py-4">
      <div className="flex items-center justify-between max-w-4xl mx-auto">
        {/* Left side */}
        <div>
          {showBack && (
            <Button variant="ghost" onClick={onBack} className="gap-2">
              <ChevronLeft className="h-4 w-4" />
              Back
            </Button>
          )}
        </div>

        {/* Right side */}
        <div className="flex items-center gap-3">
          <Button variant="outline" onClick={onSaveExit} className="gap-2">
            <Save className="h-4 w-4" />
            Save & exit
          </Button>
          {showContinue && (
            <Button onClick={onContinue} disabled={continueDisabled} className="gap-2">
              {continueLabel}
              <ArrowRight className="h-4 w-4" />
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}
