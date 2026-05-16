import { Plus, UserCheck } from "lucide-react";
import { useOutletContext } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { Application } from "@/features/onboarding/types";

interface OnboardingContext {
  application: Application;
  applicationId: string;
}

export function StepUBOs() {
  const { application } = useOutletContext<OnboardingContext>();

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-foreground">Ultimate Beneficial Owners</h1>
        <p className="text-muted-foreground mt-1">
          Add all individuals who own 25% or more of the company.
        </p>
      </div>

      {application.ubos.length === 0 ? (
        <Card className="border-dashed">
          <CardContent className="flex flex-col items-center justify-center py-12">
            <UserCheck className="h-12 w-12 text-muted-foreground mb-4" />
            <h3 className="text-lg font-medium text-foreground mb-1">No UBOs added</h3>
            <p className="text-sm text-muted-foreground mb-4 text-center max-w-sm">
              Add individuals who directly or indirectly own 25% or more of the company
            </p>
            <Button className="gap-2">
              <Plus className="h-4 w-4" />
              Add UBO
            </Button>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-4">
          {application.ubos.map((ubo) => (
            <Card key={ubo.id}>
              <CardHeader className="pb-3">
                <div className="flex items-center justify-between">
                  <CardTitle className="text-base">{ubo.full_name || "Beneficial Owner"}</CardTitle>
                  <span className="text-sm font-semibold text-primary">
                    {ubo.ownership_percentage}% ownership
                  </span>
                </div>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Full name</Label>
                    <Input defaultValue={ubo.full_name} placeholder="Full name" />
                  </div>
                  <div className="space-y-2">
                    <Label>Ownership percentage</Label>
                    <Input
                      type="number"
                      min="25"
                      max="100"
                      defaultValue={ubo.ownership_percentage}
                      placeholder="e.g., 50"
                    />
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Nationality</Label>
                    <Input defaultValue={ubo.nationality} placeholder="Nationality" />
                  </div>
                  <div className="space-y-2">
                    <Label>Date of birth</Label>
                    <Input type="date" defaultValue={ubo.date_of_birth} />
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Passport number</Label>
                    <Input defaultValue={ubo.passport_number} placeholder="Passport number" />
                  </div>
                  <div className="space-y-2 col-span-2">
                    <Label>Residential address</Label>
                    <Input defaultValue={ubo.residential_address} placeholder="Full address" />
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {application.ubos.length > 0 && (
        <Button variant="outline" className="gap-2">
          <Plus className="h-4 w-4" />
          Add another UBO
        </Button>
      )}
    </div>
  );
}
