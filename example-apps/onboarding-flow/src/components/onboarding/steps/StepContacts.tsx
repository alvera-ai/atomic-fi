import { Plus, User } from "lucide-react";
import { useOutletContext } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { Application } from "@/types/onboarding";

interface OnboardingContext {
  application: Application;
  applicationId: string;
}

const CONTACT_TYPES = [
  { value: "PRIMARY", label: "Primary Contact" },
  { value: "COMPLIANCE", label: "Compliance Contact" },
  { value: "FINANCE", label: "Finance Contact" },
];

export function StepContacts() {
  const { application } = useOutletContext<OnboardingContext>();

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-foreground">Business contacts</h1>
        <p className="text-muted-foreground mt-1">Add key contact persons for your business.</p>
      </div>

      {application.business_contacts.length === 0 ? (
        <Card className="border-dashed">
          <CardContent className="flex flex-col items-center justify-center py-12">
            <User className="h-12 w-12 text-muted-foreground mb-4" />
            <h3 className="text-lg font-medium text-foreground mb-1">No contacts added</h3>
            <p className="text-sm text-muted-foreground mb-4">
              Add your primary, compliance, and finance contacts
            </p>
            <Button className="gap-2">
              <Plus className="h-4 w-4" />
              Add contact
            </Button>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-4">
          {application.business_contacts.map((contact) => (
            <Card key={contact.id}>
              <CardHeader className="pb-3">
                <div className="flex items-center justify-between">
                  <CardTitle className="text-base">
                    {CONTACT_TYPES.find((t) => t.value === contact.type)?.label}
                  </CardTitle>
                </div>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Full name</Label>
                    <Input defaultValue={contact.full_name} placeholder="Full name" />
                  </div>
                  <div className="space-y-2">
                    <Label>Role / Title</Label>
                    <Input defaultValue={contact.role} placeholder="Job title" />
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label>Email</Label>
                    <Input type="email" defaultValue={contact.email} placeholder="Email address" />
                  </div>
                  <div className="space-y-2">
                    <Label>Phone</Label>
                    <Input type="tel" defaultValue={contact.phone} placeholder="Phone number" />
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {application.business_contacts.length > 0 && (
        <Button variant="outline" className="gap-2">
          <Plus className="h-4 w-4" />
          Add another contact
        </Button>
      )}
    </div>
  );
}
