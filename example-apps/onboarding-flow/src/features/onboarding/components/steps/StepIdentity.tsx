import { useOutletContext } from "react-router-dom";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { Application, BusinessProfile } from "@/features/onboarding/types";

interface OnboardingContext {
  application: Application;
  applicationId: string;
  updateApplication: (updates: Partial<Application>) => void;
}

export function StepIdentity() {
  const { application, updateApplication } = useOutletContext<OnboardingContext>();

  const updateProfile = (field: keyof BusinessProfile, value: string) => {
    updateApplication({
      business_profile: { ...application.business_profile, [field]: value },
    });
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-foreground">Business identity</h1>
        <p className="text-muted-foreground mt-1">Provide your business registration details.</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Legal Information</CardTitle>
          <CardDescription>Official business registration details</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="legal_name">Legal name</Label>
              <Input
                id="legal_name"
                placeholder="Enter legal business name"
                value={application.business_profile.legal_name ?? ""}
                onChange={(e) => updateProfile("legal_name", e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="trade_name">Trade name</Label>
              <Input
                id="trade_name"
                placeholder="Enter trade name (if different)"
                value={application.business_profile.trade_name ?? ""}
                onChange={(e) => updateProfile("trade_name", e.target.value)}
              />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="license_number">License number</Label>
              <Input
                id="license_number"
                placeholder="Enter license number"
                value={application.business_profile.license_number ?? ""}
                onChange={(e) => updateProfile("license_number", e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="license_expiry">License expiry date</Label>
              <Input
                id="license_expiry"
                type="date"
                value={application.business_profile.license_expiry ?? ""}
                onChange={(e) => updateProfile("license_expiry", e.target.value)}
              />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="jurisdiction">Jurisdiction</Label>
              <Select
                value={application.business_profile.jurisdiction ?? ""}
                onValueChange={(v) => updateProfile("jurisdiction", v)}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Select jurisdiction" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="dubai_mainland">Dubai Mainland</SelectItem>
                  <SelectItem value="difc">DIFC</SelectItem>
                  <SelectItem value="adgm">ADGM</SelectItem>
                  <SelectItem value="jafza">JAFZA</SelectItem>
                  <SelectItem value="dmcc">DMCC</SelectItem>
                  <SelectItem value="other">Other Free Zone</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label htmlFor="entity_type">Entity type</Label>
              <Select
                value={application.business_profile.entity_type ?? ""}
                onValueChange={(v) => updateProfile("entity_type", v)}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Select entity type" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="llc">Limited Liability Company (LLC)</SelectItem>
                  <SelectItem value="sole_prop">Sole Proprietorship</SelectItem>
                  <SelectItem value="branch">Branch Office</SelectItem>
                  <SelectItem value="fze">Free Zone Establishment (FZE)</SelectItem>
                  <SelectItem value="fzco">Free Zone Company (FZCO)</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="incorporation_date">Incorporation date</Label>
            <Input
              id="incorporation_date"
              type="date"
              className="w-1/2"
              value={application.business_profile.incorporation_date ?? ""}
              onChange={(e) => updateProfile("incorporation_date", e.target.value)}
            />
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
