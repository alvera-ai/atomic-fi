import { AlertCircle, ArrowLeft, CheckCircle, Clock, FileText, XCircle } from "lucide-react";
import { useNavigate, useParams } from "react-router-dom";
import { ThemeToggle } from "@/components/layout/ThemeToggle";
import { UserMenu } from "@/components/layout/UserMenu";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { getApplicationById } from "@/hooks/useApplication";
import { cn } from "@/lib/utils";
import type { ApplicationStatus } from "@/types/onboarding";

const STATUS_CONFIG: Record<
  ApplicationStatus,
  {
    icon: typeof CheckCircle;
    label: string;
    description: string;
    className: string;
    badgeVariant: "default" | "secondary" | "destructive" | "outline";
  }
> = {
  DRAFT: {
    icon: FileText,
    label: "Draft",
    description: "Your application is not yet submitted.",
    className: "text-muted-foreground",
    badgeVariant: "secondary",
  },
  SUBMITTED: {
    icon: Clock,
    label: "Submitted",
    description: "Your application has been submitted and is pending review.",
    className: "text-blue-500",
    badgeVariant: "default",
  },
  UNDER_REVIEW: {
    icon: Clock,
    label: "Under Review",
    description: "Our team is reviewing your application. This typically takes 2-3 business days.",
    className: "text-blue-500",
    badgeVariant: "default",
  },
  ACTION_REQUIRED: {
    icon: AlertCircle,
    label: "Action Required",
    description: "Additional information or documents are needed to proceed.",
    className: "text-amber-500",
    badgeVariant: "outline",
  },
  APPROVED: {
    icon: CheckCircle,
    label: "Approved",
    description: "Congratulations! Your application has been approved.",
    className: "text-primary",
    badgeVariant: "default",
  },
  UNABLE_TO_PROCEED: {
    icon: XCircle,
    label: "Unable to Proceed",
    description: "Unfortunately, we are unable to proceed with your application at this time.",
    className: "text-destructive",
    badgeVariant: "destructive",
  },
};

export default function StatusPage() {
  const { applicationId } = useParams<{ applicationId: string }>();
  const navigate = useNavigate();

  const application = applicationId ? getApplicationById(applicationId) : null;

  if (!application) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <Card className="max-w-md w-full mx-4">
          <CardContent className="pt-6 text-center">
            <p className="text-muted-foreground mb-4">Application not found</p>
            <Button onClick={() => navigate("/start")}>Start New Application</Button>
          </CardContent>
        </Card>
      </div>
    );
  }

  const statusConfig = STATUS_CONFIG[application.status];
  const StatusIcon = statusConfig.icon;

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="sticky top-0 z-30 flex items-center justify-between h-14 px-6 bg-background border-b border-border">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="icon" onClick={() => navigate("/start")}>
            <ArrowLeft className="h-4 w-4" />
          </Button>
          <span className="font-bold text-foreground">Application Status</span>
        </div>
        <div className="flex items-center gap-2">
          <ThemeToggle />
          <UserMenu />
        </div>
      </header>

      <main className="max-w-2xl mx-auto px-6 py-12">
        <Card>
          <CardHeader className="text-center pb-6">
            <div
              className={cn(
                "h-16 w-16 rounded-full flex items-center justify-center mx-auto mb-4",
                application.status === "APPROVED" ? "bg-primary/10" : "bg-muted",
              )}
            >
              <StatusIcon className={cn("h-8 w-8", statusConfig.className)} />
            </div>
            <Badge variant={statusConfig.badgeVariant} className="mx-auto mb-2">
              {statusConfig.label}
            </Badge>
            <CardTitle className="text-xl">
              {application.business_profile.legal_name || "Your Application"}
            </CardTitle>
            <CardDescription className="max-w-sm mx-auto">
              {statusConfig.description}
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="border-t border-border pt-4">
              <dl className="space-y-3 text-sm">
                <div className="flex justify-between">
                  <dt className="text-muted-foreground">Application ID</dt>
                  <dd className="font-mono text-foreground">{application.application_id}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-muted-foreground">Submitted</dt>
                  <dd className="text-foreground">
                    {new Date(application.updated_at).toLocaleDateString()}
                  </dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-muted-foreground">Method</dt>
                  <dd className="text-foreground">
                    {application.onboarding_method === "UPLOAD_PREFILL"
                      ? "Upload & Prefill"
                      : "Manual Entry"}
                  </dd>
                </div>
              </dl>
            </div>

            {application.status === "ACTION_REQUIRED" && (
              <div className="bg-amber-50 dark:bg-amber-950/20 border border-amber-200 dark:border-amber-800 rounded-lg p-4">
                <p className="text-sm text-amber-800 dark:text-amber-200">
                  Please check your email for details on what additional information is needed.
                </p>
              </div>
            )}

            {application.status === "DRAFT" && (
              <Button
                className="w-full"
                onClick={() => navigate(`/onboarding/${applicationId}/documents`)}
              >
                Continue Application
              </Button>
            )}
          </CardContent>
        </Card>
      </main>
    </div>
  );
}
