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
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import type { Application } from "@/types/onboarding";

interface OnboardingContext {
  application: Application;
  applicationId: string;
}

export function StepTransfers() {
  const { application } = useOutletContext<OnboardingContext>();

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-foreground">Expected transfer behavior</h1>
        <p className="text-muted-foreground mt-1">
          Tell us about your expected UAE to US transfer patterns.
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Transfer Volume</CardTitle>
          <CardDescription>Estimate your monthly transfer activity</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="monthly_volume">Expected monthly volume (USD)</Label>
              <Input
                id="monthly_volume"
                type="number"
                placeholder="e.g., 100000"
                defaultValue={application.transfer_behavior.expected_monthly_volume_usd}
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="monthly_transactions">Expected monthly transactions</Label>
              <Input
                id="monthly_transactions"
                type="number"
                placeholder="e.g., 20"
                defaultValue={application.transfer_behavior.expected_monthly_transactions}
              />
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="transfer_purpose">Primary transfer purpose</Label>
            <Select defaultValue={application.transfer_behavior.primary_transfer_purpose}>
              <SelectTrigger>
                <SelectValue placeholder="Select purpose" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="supplier_payments">Supplier Payments</SelectItem>
                <SelectItem value="payroll">Payroll / Contractor Payments</SelectItem>
                <SelectItem value="investment">Investment / Capital Transfer</SelectItem>
                <SelectItem value="services">Service Fees</SelectItem>
                <SelectItem value="licensing">Licensing / Royalties</SelectItem>
                <SelectItem value="other">Other</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="counterparties">Expected counterparties</Label>
            <Textarea
              id="counterparties"
              placeholder="Describe your typical counterparties (suppliers, partners, etc.)"
              defaultValue={application.transfer_behavior.expected_counterparties?.join(", ")}
              rows={2}
            />
          </div>

          <div className="flex items-center justify-between p-4 bg-muted/50 rounded-lg">
            <div>
              <Label htmlFor="high_risk" className="text-sm font-medium">
                High-risk jurisdictions
              </Label>
              <p className="text-xs text-muted-foreground mt-0.5">
                Will you transact with sanctioned or high-risk countries?
              </p>
            </div>
            <Switch
              id="high_risk"
              defaultChecked={application.transfer_behavior.high_risk_jurisdictions}
            />
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
