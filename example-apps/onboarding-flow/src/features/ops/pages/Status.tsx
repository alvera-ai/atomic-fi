import {
  AlertCircle,
  ArrowLeft,
  Building,
  CheckCircle,
  Clock,
  FileText,
  Globe,
  Loader2,
  MapPin,
  Shield,
  UserCheck,
  XCircle,
} from "lucide-react";
import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { ThemeToggle } from "@/components/layout/ThemeToggle";
import { UserMenu } from "@/components/layout/UserMenu";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { fetchSubmissionDetails, type SubmissionDetails } from "@/features/onboarding/api";
import { getApplicationById } from "@/features/onboarding/store";
import type { ApplicationStatus } from "@/features/onboarding/types";
import { cn } from "@/lib/utils";

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

function DetailRow({ label, value }: { label: string; value: string | undefined | null }) {
  if (!value) return null;
  return (
    <div className="flex justify-between gap-4">
      <dt className="text-muted-foreground shrink-0">{label}</dt>
      <dd className="text-foreground text-right">{value}</dd>
    </div>
  );
}

function MonoRow({ label, value }: { label: string; value: string | undefined | null }) {
  if (!value) return null;
  return (
    <div className="flex justify-between gap-4">
      <dt className="text-muted-foreground shrink-0">{label}</dt>
      <dd className="font-mono text-xs text-foreground text-right">{value}</dd>
    </div>
  );
}

function formatStatus(s: string) {
  return s.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

function AccountHolderCard({ ah }: { ah: SubmissionDetails["accountHolder"] }) {
  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center gap-2">
          <UserCheck className="h-4 w-4 text-primary" />
          <CardTitle className="text-base">Account Holder</CardTitle>
        </div>
      </CardHeader>
      <CardContent>
        <dl className="space-y-3 text-sm">
          <MonoRow label="ID" value={ah.id} />
          <DetailRow label="Type" value={formatStatus(ah.holder_type)} />
          <DetailRow label="Status" value={formatStatus(ah.status ?? "")} />
          <DetailRow label="KYC Status" value={formatStatus(ah.kyc_status ?? "")} />
          <DetailRow label="Risk Level" value={formatStatus(ah.risk_level ?? "")} />
          <DetailRow label="Currencies" value={ah.enabled_currencies?.join(", ")} />
          <DetailRow label="Created" value={ah.inserted_at?.replace("T", " ").slice(0, 19)} />
        </dl>
      </CardContent>
    </Card>
  );
}

function LegalEntityCard({ le }: { le: SubmissionDetails["legalEntity"] }) {
  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center gap-2">
          <Building className="h-4 w-4 text-primary" />
          <CardTitle className="text-base">Legal Entity</CardTitle>
        </div>
      </CardHeader>
      <CardContent className="space-y-4">
        <dl className="space-y-3 text-sm">
          <MonoRow label="ID" value={le.id} />
          <DetailRow label="Type" value={formatStatus(le.legal_entity_type)} />
          <DetailRow label="Business Name" value={le.business_name} />
          {le.doing_business_as_names && le.doing_business_as_names.length > 0 && (
            <DetailRow label="DBA" value={le.doing_business_as_names.join(", ")} />
          )}
          <DetailRow label="Legal Structure" value={formatStatus(le.legal_structure ?? "")} />
          <DetailRow label="Date Formed" value={le.date_formed} />
          <DetailRow label="Citizenship" value={le.citizenship_country} />
        </dl>

        {le.addresses && le.addresses.length > 0 && (
          <div className="border-t border-border pt-3">
            <div className="flex items-center gap-2 mb-2">
              <MapPin className="h-3.5 w-3.5 text-muted-foreground" />
              <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                Addresses
              </span>
            </div>
            {le.addresses.map((addr) => (
              <div
                key={`${addr.line1}-${addr.locality}`}
                className="text-sm text-foreground ml-5.5"
              >
                <p>
                  {addr.line1}
                  {addr.line2 ? `, ${addr.line2}` : ""}
                </p>
                <p className="text-muted-foreground">
                  {[addr.locality, addr.region, addr.postal_code, addr.country]
                    .filter(Boolean)
                    .join(", ")}
                </p>
                <div className="flex gap-1 mt-1">
                  {addr.primary && (
                    <Badge variant="outline" className="text-[10px] h-4">
                      Primary
                    </Badge>
                  )}
                  {addr.address_types?.map((t) => (
                    <Badge key={t} variant="secondary" className="text-[10px] h-4">
                      {t}
                    </Badge>
                  ))}
                </div>
              </div>
            ))}
          </div>
        )}

        {le.identifications && le.identifications.length > 0 && (
          <div className="border-t border-border pt-3">
            <div className="flex items-center gap-2 mb-2">
              <Globe className="h-3.5 w-3.5 text-muted-foreground" />
              <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
                Identifications
              </span>
            </div>
            {le.identifications.map((ident) => (
              <dl key={ident.id_type} className="space-y-1 text-sm ml-5.5">
                <DetailRow label="Type" value={formatStatus(ident.id_type)} />
                <DetailRow label="Number" value={ident.id_number} />
                <DetailRow label="Issuing Country" value={ident.issuing_country} />
              </dl>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function KycRequirementCard({ kyc }: { kyc: SubmissionDetails["kycRequirement"] }) {
  return (
    <Card>
      <CardHeader className="pb-3">
        <div className="flex items-center gap-2">
          <Shield className="h-4 w-4 text-primary" />
          <CardTitle className="text-base">KYC Requirement</CardTitle>
        </div>
      </CardHeader>
      <CardContent>
        <dl className="space-y-3 text-sm">
          <MonoRow label="ID" value={kyc.id} />
          <DetailRow label="Scope" value={formatStatus(kyc.scope)} />
          <DetailRow label="Requirement" value={formatStatus(kyc.requirement_type)} />
          <DetailRow label="Status" value={formatStatus(kyc.status ?? "")} />
          <MonoRow label="Document ID" value={kyc.document_id} />
        </dl>
      </CardContent>
    </Card>
  );
}

export default function StatusPage() {
  const { applicationId } = useParams<{ applicationId: string }>();
  const navigate = useNavigate();
  const application = applicationId ? getApplicationById(applicationId) : null;

  const [details, setDetails] = useState<SubmissionDetails | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!application?.api_result) return;
    setLoading(true);
    fetchSubmissionDetails(application.api_result)
      .then(setDetails)
      .finally(() => setLoading(false));
  }, [application?.api_result]);

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

      <main className="max-w-2xl mx-auto px-6 py-12 space-y-6">
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
          <CardContent>
            <dl className="space-y-3 text-sm">
              <MonoRow label="Application ID" value={application.application_id} />
              <DetailRow
                label="Submitted"
                value={new Date(application.updated_at).toLocaleDateString()}
              />
              <DetailRow
                label="Method"
                value={
                  application.onboarding_method === "UPLOAD_PREFILL"
                    ? "Upload & Prefill"
                    : "Manual Entry"
                }
              />
            </dl>
          </CardContent>
        </Card>

        {loading && (
          <div className="flex items-center justify-center py-8 text-muted-foreground gap-2">
            <Loader2 className="h-4 w-4 animate-spin" />
            <span className="text-sm">Loading entity details...</span>
          </div>
        )}

        {details?.accountHolder && <AccountHolderCard ah={details.accountHolder} />}
        {details?.legalEntity && <LegalEntityCard le={details.legalEntity} />}
        {details?.kycRequirement && <KycRequirementCard kyc={details.kycRequirement} />}

        {application.api_result && !details && !loading && (
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="text-base">Created Entities</CardTitle>
              <CardDescription>API details unavailable — showing IDs only</CardDescription>
            </CardHeader>
            <CardContent>
              <dl className="space-y-3 text-sm">
                <MonoRow label="Account Holder" value={application.api_result.accountHolderId} />
                <MonoRow label="Legal Entity" value={application.api_result.legalEntityId} />
                <MonoRow label="KYC Requirement" value={application.api_result.kycRequirementId} />
              </dl>
            </CardContent>
          </Card>
        )}

        {application.status === "ACTION_REQUIRED" && (
          <Card className="border-amber-200 dark:border-amber-800">
            <CardContent className="pt-4">
              <p className="text-sm text-amber-800 dark:text-amber-200">
                Please check your email for details on what additional information is needed.
              </p>
            </CardContent>
          </Card>
        )}

        {application.status === "DRAFT" && (
          <Button
            className="w-full"
            onClick={() => navigate(`/onboarding/${applicationId}/documents`)}
          >
            Continue Application
          </Button>
        )}
      </main>
    </div>
  );
}
