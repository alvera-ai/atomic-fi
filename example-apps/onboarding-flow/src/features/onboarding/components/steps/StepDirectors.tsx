import { Plus, Users } from "lucide-react";
import { useOutletContext } from "react-router-dom";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import type { Application } from "@/features/onboarding/types";

interface OnboardingContext {
  application: Application;
  applicationId: string;
}

export function StepDirectors() {
  const { application } = useOutletContext<OnboardingContext>();

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-foreground">Directors & signatories</h1>
        <p className="text-muted-foreground mt-1">Add all directors and authorized signatories.</p>
      </div>

      {application.directors.length === 0 ? (
        <Card className="border-dashed">
          <CardContent className="flex flex-col items-center justify-center py-12">
            <Users className="h-12 w-12 text-muted-foreground mb-4" />
            <h3 className="text-lg font-medium text-foreground mb-1">No directors added</h3>
            <p className="text-sm text-muted-foreground mb-4">
              Add your company directors and signatories
            </p>
            <Button className="gap-2">
              <Plus className="h-4 w-4" />
              Add director
            </Button>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-4">
          {application.directors.map((director) => (
            <Card key={director.id}>
              <CardHeader className="pb-3">
                <div className="flex items-center justify-between">
                  <CardTitle className="text-base">{director.full_name || "Director"}</CardTitle>
                  <div className="flex items-center gap-2">
                    {director.is_signatory && <Badge variant="secondary">Signatory</Badge>}
                  </div>
                </div>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Full name</Label>
                    <Input defaultValue={director.full_name} placeholder="Full name" />
                  </div>
                  <div className="space-y-2">
                    <Label>Nationality</Label>
                    <Input defaultValue={director.nationality} placeholder="Nationality" />
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Date of birth</Label>
                    <Input type="date" defaultValue={director.date_of_birth} />
                  </div>
                  <div className="space-y-2">
                    <Label>Passport number</Label>
                    <Input defaultValue={director.passport_number} placeholder="Passport number" />
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Email</Label>
                    <Input type="email" defaultValue={director.email} placeholder="Email" />
                  </div>
                  <div className="space-y-2">
                    <Label>Phone</Label>
                    <Input type="tel" defaultValue={director.phone} placeholder="Phone" />
                  </div>
                </div>
                <div className="flex items-center gap-3 pt-2">
                  <Switch id={`signatory-${director.id}`} defaultChecked={director.is_signatory} />
                  <Label htmlFor={`signatory-${director.id}`}>Authorized signatory</Label>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {application.directors.length > 0 && (
        <Button variant="outline" className="gap-2">
          <Plus className="h-4 w-4" />
          Add another director
        </Button>
      )}
    </div>
  );
}
