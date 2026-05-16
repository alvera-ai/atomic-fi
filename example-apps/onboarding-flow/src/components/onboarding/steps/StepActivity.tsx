import { useOutletContext } from "react-router-dom";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Application } from "@/types/onboarding";

interface OnboardingContext {
  application: Application;
  applicationId: string;
}

export function StepActivity() {
  const { application } = useOutletContext<OnboardingContext>();

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-foreground">Business activity & purpose</h1>
        <p className="text-muted-foreground mt-1">
          Describe your business operations and purpose of account.
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Business Activities</CardTitle>
          <CardDescription>
            What does your business do?
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="primary_activity">Primary activity</Label>
            <Select defaultValue={application.business_activity.primary_activity}>
              <SelectTrigger>
                <SelectValue placeholder="Select primary activity" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="trading">Trading / Import-Export</SelectItem>
                <SelectItem value="consulting">Consulting / Professional Services</SelectItem>
                <SelectItem value="technology">Technology / Software</SelectItem>
                <SelectItem value="manufacturing">Manufacturing</SelectItem>
                <SelectItem value="real_estate">Real Estate</SelectItem>
                <SelectItem value="retail">Retail / E-commerce</SelectItem>
                <SelectItem value="hospitality">Hospitality / Tourism</SelectItem>
                <SelectItem value="other">Other</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="purpose">Purpose of account</Label>
            <Textarea
              id="purpose"
              placeholder="Describe why you need a US business account..."
              defaultValue={application.business_activity.purpose_of_account}
              rows={3}
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="source_of_funds">Source of funds</Label>
            <Select defaultValue={application.business_activity.source_of_funds}>
              <SelectTrigger>
                <SelectValue placeholder="Select source of funds" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="business_revenue">Business Revenue</SelectItem>
                <SelectItem value="investment">Investment Capital</SelectItem>
                <SelectItem value="loan">Business Loan</SelectItem>
                <SelectItem value="personal_funds">Personal Funds</SelectItem>
                <SelectItem value="mixed">Mixed Sources</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
