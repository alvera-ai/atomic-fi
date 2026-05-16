import { ArrowRight, Clock, FileText, PenLine, Upload } from "lucide-react";
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { ThemeToggle } from "@/components/layout/ThemeToggle";
import { UserMenu } from "@/components/layout/UserMenu";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { createNewApplication, getAllApplications, saveApplication } from "@/hooks/useApplication";
import { cn } from "@/lib/utils";
import type { Application, OnboardingMethod } from "@/types/onboarding";

export default function StartPage() {
  const navigate = useNavigate();
  const [selectedMethod, setSelectedMethod] = useState<OnboardingMethod | null>(null);

  const existingApplications = getAllApplications().filter((app) => app.status === "DRAFT");

  const handleCreateApplication = () => {
    if (!selectedMethod) return;

    const newApp = createNewApplication(selectedMethod);
    saveApplication(newApp);
    navigate(`/onboarding/${newApp.application_id}/documents`);
  };

  const handleResumeApplication = (app: Application) => {
    const stepPaths = [
      "documents",
      "identity",
      "addresses",
      "contacts",
      "activity",
      "transfers",
      "ownership",
      "directors",
      "ubos",
      "review",
    ];
    const currentPath = stepPaths[app.current_step - 1] || "documents";
    navigate(`/onboarding/${app.application_id}/${currentPath}`);
  };

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="sticky top-0 z-30 flex items-center justify-between h-14 px-6 bg-background border-b border-border">
        <div className="flex items-center gap-3">
          <span className="font-bold text-lg text-foreground">Business Onboarding</span>
          <span className="text-muted-foreground">Dubai → US</span>
        </div>
        <div className="flex items-center gap-2">
          <ThemeToggle />
          <UserMenu />
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-6 py-12">
        <div className="text-center mb-10">
          <h1 className="text-3xl font-bold text-foreground mb-2">Start your application</h1>
          <p className="text-muted-foreground">
            Open a US business account for your UAE-based company
          </p>
        </div>

        {/* Resume existing applications */}
        {existingApplications.length > 0 && (
          <div className="mb-8">
            <h2 className="text-sm font-medium text-muted-foreground mb-3">
              Resume saved application
            </h2>
            <div className="space-y-3">
              {existingApplications.map((app) => (
                <Card
                  key={app.application_id}
                  className="cursor-pointer hover:border-primary/50 transition-colors"
                  onClick={() => handleResumeApplication(app)}
                >
                  <CardContent className="flex items-center justify-between py-4">
                    <div className="flex items-center gap-4">
                      <div className="h-10 w-10 rounded-full bg-muted flex items-center justify-center">
                        <FileText className="h-5 w-5 text-muted-foreground" />
                      </div>
                      <div>
                        <p className="font-medium text-foreground">
                          {app.business_profile.legal_name || "Untitled Application"}
                        </p>
                        <p className="text-sm text-muted-foreground flex items-center gap-1">
                          <Clock className="h-3 w-3" />
                          Last updated {new Date(app.updated_at).toLocaleDateString()}
                        </p>
                      </div>
                    </div>
                    <ArrowRight className="h-5 w-5 text-muted-foreground" />
                  </CardContent>
                </Card>
              ))}
            </div>
          </div>
        )}

        {/* Choose onboarding method */}
        <div>
          <h2 className="text-sm font-medium text-muted-foreground mb-3">Create new application</h2>
          <div className="grid grid-cols-2 gap-4 mb-6">
            <Card
              className={cn(
                "cursor-pointer transition-all",
                selectedMethod === "UPLOAD_PREFILL"
                  ? "border-primary ring-2 ring-primary/20"
                  : "hover:border-primary/50",
              )}
              onClick={() => setSelectedMethod("UPLOAD_PREFILL")}
            >
              <CardHeader className="text-center pb-2">
                <div className="h-12 w-12 rounded-full bg-primary/10 flex items-center justify-center mx-auto mb-3">
                  <Upload className="h-6 w-6 text-primary" />
                </div>
                <CardTitle className="text-base">Upload & prefill</CardTitle>
              </CardHeader>
              <CardContent className="text-center">
                <CardDescription>
                  Upload your documents and we'll extract information automatically
                </CardDescription>
              </CardContent>
            </Card>

            <Card
              className={cn(
                "cursor-pointer transition-all",
                selectedMethod === "MANUAL"
                  ? "border-primary ring-2 ring-primary/20"
                  : "hover:border-primary/50",
              )}
              onClick={() => setSelectedMethod("MANUAL")}
            >
              <CardHeader className="text-center pb-2">
                <div className="h-12 w-12 rounded-full bg-muted flex items-center justify-center mx-auto mb-3">
                  <PenLine className="h-6 w-6 text-muted-foreground" />
                </div>
                <CardTitle className="text-base">Manual entry</CardTitle>
              </CardHeader>
              <CardContent className="text-center">
                <CardDescription>
                  Fill in all information manually without document upload
                </CardDescription>
              </CardContent>
            </Card>
          </div>

          <Button
            className="w-full"
            size="lg"
            disabled={!selectedMethod}
            onClick={handleCreateApplication}
          >
            Start Application
            <ArrowRight className="h-4 w-4 ml-2" />
          </Button>
        </div>
      </main>
    </div>
  );
}
