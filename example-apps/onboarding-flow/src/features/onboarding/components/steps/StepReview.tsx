import {
  AlertCircle,
  ArrowRightLeft,
  Briefcase,
  Building,
  CheckCircle,
  FileText,
  Loader2,
  MapPin,
  Network,
  UserCheck,
  Users,
} from "lucide-react";
import { useState } from "react";
import { useNavigate, useOutletContext } from "react-router-dom";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Label } from "@/components/ui/label";
import { submitOnboarding } from "@/features/onboarding/api";
import { ONBOARDING_STEPS } from "@/features/onboarding/constants";
import { saveApplication } from "@/features/onboarding/store";
import type { Application } from "@/features/onboarding/types";
import { useApplication } from "@/features/onboarding/useApplication";
import { cn } from "@/lib/utils";

interface OnboardingContext {
  application: Application;
  applicationId: string;
}

const STEP_ICONS: Record<number, typeof FileText> = {
  1: FileText,
  2: Building,
  3: MapPin,
  4: Users,
  5: Briefcase,
  6: ArrowRightLeft,
  7: Network,
  8: Users,
  9: UserCheck,
  10: CheckCircle,
};

export function StepReview() {
  const { application, applicationId } = useOutletContext<OnboardingContext>();
  const navigate = useNavigate();
  const { updateApplication } = useApplication(applicationId);
  const [submitting, setSubmitting] = useState(false);

  const incompleteSteps = ONBOARDING_STEPS.filter(
    (step) => !application.completed_steps.includes(step.id) && step.id !== 10,
  );

  const apiConfigured = !!(import.meta.env.VITE_API_KEY && import.meta.env.VITE_TENANT_ID);

  const markSubmitted = () => {
    const updatedApp = {
      ...application,
      status: "SUBMITTED" as const,
      updated_at: new Date().toISOString(),
    };
    saveApplication(updatedApp);
    return updatedApp;
  };

  const handleSubmit = async () => {
    if (incompleteSteps.length > 0) {
      toast.error("Please complete all steps before submitting");
      return;
    }

    if (
      !application.submission_confirmations.confirm_accuracy ||
      !application.submission_confirmations.confirm_authority
    ) {
      toast.error("Please confirm all declarations before submitting");
      return;
    }

    setSubmitting(true);

    if (!apiConfigured) {
      markSubmitted();
      toast.success("Application submitted (localStorage only — API not configured)");
      navigate(`/status/${applicationId}`);
      setSubmitting(false);
      return;
    }

    try {
      const result = await submitOnboarding(application);
      markSubmitted();
      toast.success("Application submitted successfully!", {
        description: `AccountHolder: ${result.accountHolderId}`,
      });
      navigate(`/status/${applicationId}`);
    } catch (err) {
      const message = err instanceof Error ? err.message : "Unknown error";
      toast.error("Submission failed", { description: message });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-foreground">Review & submit</h1>
        <p className="text-muted-foreground mt-1">Review your application before submitting.</p>
      </div>

      {!apiConfigured && (
        <Card className="border-amber-500/50 bg-amber-500/5">
          <CardContent className="pt-4">
            <p className="text-sm text-amber-700 dark:text-amber-400">
              API not configured. Set <code className="font-mono text-xs">VITE_API_KEY</code> and{" "}
              <code className="font-mono text-xs">VITE_TENANT_ID</code> in{" "}
              <code className="font-mono text-xs">.env.local</code> to submit to the backend.
            </p>
          </CardContent>
        </Card>
      )}

      {/* Steps completion status */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Application Checklist</CardTitle>
          <CardDescription>All steps must be completed before submission</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-2">
            {ONBOARDING_STEPS.slice(0, -1).map((step) => {
              const isComplete = application.completed_steps.includes(step.id);
              const Icon = STEP_ICONS[step.id] || FileText;

              return (
                <div
                  key={step.id}
                  className={cn(
                    "flex items-center justify-between p-3 rounded-lg transition-colors",
                    isComplete ? "bg-primary/5" : "bg-muted/50",
                  )}
                >
                  <div className="flex items-center gap-3">
                    <Icon
                      className={cn(
                        "h-4 w-4",
                        isComplete ? "text-primary" : "text-muted-foreground",
                      )}
                    />
                    <span
                      className={cn("text-sm font-medium", !isComplete && "text-muted-foreground")}
                    >
                      {step.title}
                    </span>
                  </div>
                  {isComplete ? (
                    <CheckCircle className="h-4 w-4 text-primary" />
                  ) : (
                    <Badge variant="outline" className="text-xs">
                      <AlertCircle className="h-3 w-3 mr-1" />
                      Incomplete
                    </Badge>
                  )}
                </div>
              );
            })}
          </div>
        </CardContent>
      </Card>

      {/* Confirmations */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Declarations</CardTitle>
          <CardDescription>Please confirm the following before submitting</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-start gap-3">
            <Checkbox
              id="confirm_accuracy"
              checked={application.submission_confirmations.confirm_accuracy}
              onCheckedChange={(checked) => {
                updateApplication({
                  submission_confirmations: {
                    ...application.submission_confirmations,
                    confirm_accuracy: !!checked,
                  },
                });
              }}
            />
            <Label htmlFor="confirm_accuracy" className="text-sm leading-relaxed cursor-pointer">
              I confirm that all information provided in this application is true, accurate, and
              complete to the best of my knowledge.
            </Label>
          </div>

          <div className="flex items-start gap-3">
            <Checkbox
              id="confirm_authority"
              checked={application.submission_confirmations.confirm_authority}
              onCheckedChange={(checked) => {
                updateApplication({
                  submission_confirmations: {
                    ...application.submission_confirmations,
                    confirm_authority: !!checked,
                  },
                });
              }}
            />
            <Label htmlFor="confirm_authority" className="text-sm leading-relaxed cursor-pointer">
              I confirm that I am authorized to submit this application on behalf of the business
              entity and bind it to the terms and conditions.
            </Label>
          </div>
        </CardContent>
      </Card>

      {/* Submit button */}
      <div className="flex justify-end pt-4">
        <Button
          size="lg"
          onClick={handleSubmit}
          disabled={incompleteSteps.length > 0 || submitting}
          className="gap-2"
        >
          {submitting ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <CheckCircle className="h-4 w-4" />
          )}
          {submitting ? "Submitting..." : "Submit Application"}
        </Button>
      </div>
    </div>
  );
}
