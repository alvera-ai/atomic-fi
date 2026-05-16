import { Upload } from "lucide-react";
import { useOutletContext } from "react-router-dom";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import type { Application } from "@/types/onboarding";

interface OnboardingContext {
  application: Application;
  applicationId: string;
}

export function StepOwnership() {
  const { application } = useOutletContext<OnboardingContext>();

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-foreground">Ownership structure</h1>
        <p className="text-muted-foreground mt-1">
          Provide details about your company's ownership.
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Corporate Structure</CardTitle>
          <CardDescription>Is your company a subsidiary of another entity?</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between p-4 bg-muted/50 rounded-lg">
            <div>
              <Label htmlFor="is_subsidiary" className="text-sm font-medium">
                Subsidiary company
              </Label>
              <p className="text-xs text-muted-foreground mt-0.5">
                Is this company owned by a parent entity?
              </p>
            </div>
            <Switch
              id="is_subsidiary"
              defaultChecked={application.ownership_structure.is_subsidiary}
            />
          </div>

          {application.ownership_structure.is_subsidiary && (
            <div className="space-y-4 pt-2">
              <div className="space-y-2">
                <Label htmlFor="parent_name">Parent company name</Label>
                <Input
                  id="parent_name"
                  placeholder="Enter parent company name"
                  defaultValue={application.ownership_structure.parent_company_name}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="parent_jurisdiction">Parent company jurisdiction</Label>
                <Input
                  id="parent_jurisdiction"
                  placeholder="e.g., United States, Delaware"
                  defaultValue={application.ownership_structure.parent_company_jurisdiction}
                />
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Ownership Chart</CardTitle>
          <CardDescription>Upload an ownership structure diagram (optional)</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="border-2 border-dashed border-border rounded-lg p-6 text-center hover:border-primary/50 hover:bg-muted/30 transition-colors cursor-pointer">
            <Upload className="h-8 w-8 mx-auto text-muted-foreground mb-2" />
            <p className="text-sm text-muted-foreground">Drag & drop or click to upload</p>
            <p className="text-xs text-muted-foreground mt-1">PDF, JPG, PNG up to 10MB</p>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
