import { MapPin, Plus } from "lucide-react";
import { useOutletContext } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { Application } from "@/features/onboarding/types";

interface OnboardingContext {
  application: Application;
  applicationId: string;
}

const ADDRESS_TYPES = [
  { value: "REGISTERED", label: "Registered Address" },
  { value: "OPERATING", label: "Operating Address" },
  { value: "CORRESPONDENCE", label: "Correspondence Address" },
];

export function StepAddresses() {
  const { application } = useOutletContext<OnboardingContext>();

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-foreground">Addresses</h1>
        <p className="text-muted-foreground mt-1">
          Provide your business registered and operating addresses.
        </p>
      </div>

      {application.addresses.length === 0 ? (
        <Card className="border-dashed">
          <CardContent className="flex flex-col items-center justify-center py-12">
            <MapPin className="h-12 w-12 text-muted-foreground mb-4" />
            <h3 className="text-lg font-medium text-foreground mb-1">No addresses added</h3>
            <p className="text-sm text-muted-foreground mb-4">
              Add your registered and operating addresses
            </p>
            <Button className="gap-2">
              <Plus className="h-4 w-4" />
              Add address
            </Button>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-4">
          {application.addresses.map((address) => (
            <Card key={address.id}>
              <CardHeader className="pb-3">
                <CardTitle className="text-base">
                  {ADDRESS_TYPES.find((t) => t.value === address.type)?.label}
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label>Address line 1</Label>
                  <Input defaultValue={address.line1} placeholder="Street address" />
                </div>
                <div className="space-y-2">
                  <Label>Address line 2</Label>
                  <Input defaultValue={address.line2} placeholder="Suite, floor, etc." />
                </div>
                <div className="grid grid-cols-3 gap-4">
                  <div className="space-y-2">
                    <Label>City</Label>
                    <Input defaultValue={address.city} placeholder="City" />
                  </div>
                  <div className="space-y-2">
                    <Label>Emirate</Label>
                    <Input defaultValue={address.emirate} placeholder="Emirate" />
                  </div>
                  <div className="space-y-2">
                    <Label>Country</Label>
                    <Input defaultValue={address.country} placeholder="Country" />
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {application.addresses.length > 0 && (
        <Button variant="outline" className="gap-2">
          <Plus className="h-4 w-4" />
          Add another address
        </Button>
      )}

      {/* Empty state form for first address */}
      {application.addresses.length === 0 && (
        <Card className="hidden">
          <CardHeader>
            <CardTitle className="text-base">Add Address</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-2">
              <Label>Address type</Label>
              <Select>
                <SelectTrigger>
                  <SelectValue placeholder="Select type" />
                </SelectTrigger>
                <SelectContent>
                  {ADDRESS_TYPES.map((type) => (
                    <SelectItem key={type.value} value={type.value}>
                      {type.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
