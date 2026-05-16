import { useState } from "react";
import { useOutletContext } from "react-router-dom";
import { Upload, FileText, AlertCircle, CheckCircle, Loader2, Eye, Sparkles, AlertTriangle } from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { cn } from "@/lib/utils";
import { toast } from "sonner";
import {
  Application,
  DocumentType,
  DOCUMENT_TYPE_LABELS,
  DocumentStatus,
  UploadMode,
} from "@/types/onboarding";
import { SAMPLE_DOCUMENTS, buildSampleDocument } from "@/data/sampleDocuments";
import { DocumentPreviewModal } from "../DocumentPreviewModal";
import { BulkUploadZone } from "../BulkUploadZone";
import { DocumentVerificationBadge } from "../DocumentVerificationBadge";
import { summarizeVerification } from "@/lib/documentVerification";

interface OnboardingContext {
  application: Application;
  applicationId: string;
  updateApplication: (updates: Partial<Application>) => void;
}

const REQUIRED_DOCUMENTS: DocumentType[] = [
  "TRADE_LICENSE",
  "MEMORANDUM_OF_ASSOCIATION",
  "CERTIFICATE_OF_INCORPORATION",
  "PASSPORT",
  "EMIRATES_ID",
  "PROOF_OF_ADDRESS",
  "BANK_STATEMENT",
];

const STATUS_CONFIG: Record<
  DocumentStatus,
  { icon: typeof CheckCircle; label: string; className: string }
> = {
  UPLOADED: { icon: Loader2, label: "Processing", className: "text-blue-500" },
  PROCESSING: { icon: Loader2, label: "Extracting", className: "text-blue-500 animate-spin" },
  EXTRACTED: { icon: CheckCircle, label: "Ready", className: "text-primary" },
  NEEDS_ATTENTION: { icon: AlertCircle, label: "Needs attention", className: "text-destructive" },
};

export function StepDocuments() {
  const { application, updateApplication } = useOutletContext<OnboardingContext>();
  const [previewDoc, setPreviewDoc] = useState<{
    docType: DocumentType;
    filename?: string;
  } | null>(null);

  const mode: UploadMode = application.upload_mode ?? "BULK";
  const setMode = (m: UploadMode) => updateApplication({ upload_mode: m });

  const summary = summarizeVerification(application.documents.map((d) => d.verification));

  const getDocumentsForType = (docType: DocumentType) =>
    application.documents.filter((d) => d.doc_type === docType);

  const handleUseSample = (docType: DocumentType) => {
    const sample = SAMPLE_DOCUMENTS[docType];
    if (!sample) return;

    const newDoc = buildSampleDocument(sample);
    const prefill = sample.applyPrefill(application);
    const newProvenance = {
      ...application.field_provenance,
      ...sample.provenance,
    };

    updateApplication({
      ...prefill,
      documents: [...application.documents, newDoc],
      field_provenance: newProvenance,
    });

    toast.success(`Sample ${DOCUMENT_TYPE_LABELS[docType]} attached`, {
      description: "Fields prefilled with extracted data",
    });
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-foreground">Upload documents</h1>
        <p className="text-muted-foreground mt-1">
          Choose how you'd like to upload — drop everything at once and we'll sort it, or upload
          one document per category.
        </p>
      </div>

      {(summary.fail > 0 || summary.warn > 0) && (
        <Alert variant={summary.fail > 0 ? "destructive" : "default"}>
          <AlertTriangle className="h-4 w-4" />
          <AlertTitle>
            {summary.fail > 0
              ? `${summary.fail} document${summary.fail > 1 ? "s" : ""} rejected`
              : `${summary.warn} document${summary.warn > 1 ? "s" : ""} need review`}
          </AlertTitle>
          <AlertDescription>
            Verification flagged issues with one or more uploads. Review the badges below and
            replace files where needed.
          </AlertDescription>
        </Alert>
      )}

      <Tabs value={mode} onValueChange={(v) => setMode(v as UploadMode)}>
        <TabsList className="grid w-full max-w-md grid-cols-2">
          <TabsTrigger value="BULK">Bulk dump</TabsTrigger>
          <TabsTrigger value="INDIVIDUAL">One by one</TabsTrigger>
        </TabsList>

        <TabsContent value="BULK" className="mt-6">
          <BulkUploadZone application={application} updateApplication={updateApplication} />

          {application.documents.length > 0 && (
            <div className="mt-6 space-y-2">
              <h3 className="text-sm font-medium">Uploaded documents</h3>
              <div className="space-y-2">
                {application.documents.map((doc) => {
                  const statusConfig = STATUS_CONFIG[doc.status];
                  const StatusIcon = statusConfig.icon;
                  return (
                    <div
                      key={doc.file_id}
                      className="flex items-center justify-between p-3 bg-muted/40 rounded-lg border"
                    >
                      <div className="flex items-center gap-3 min-w-0">
                        <FileText className="h-4 w-4 text-muted-foreground shrink-0" />
                        <div className="min-w-0">
                          <div className="text-sm font-medium truncate">{doc.filename}</div>
                          <div className="text-xs text-muted-foreground">
                            {DOCUMENT_TYPE_LABELS[doc.doc_type]}
                          </div>
                        </div>
                      </div>
                      <div className="flex items-center gap-3 shrink-0">
                        <DocumentVerificationBadge result={doc.verification} />
                        <div className={cn("flex items-center gap-1.5 text-xs", statusConfig.className)}>
                          <StatusIcon className="h-3.5 w-3.5" />
                          <span>{statusConfig.label}</span>
                        </div>
                        <Button
                          variant="ghost"
                          size="sm"
                          className="h-7 gap-1.5 text-xs"
                          onClick={() => setPreviewDoc({ docType: doc.doc_type, filename: doc.filename })}
                        >
                          <Eye className="h-3.5 w-3.5" />
                          Preview
                        </Button>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}
        </TabsContent>

        <TabsContent value="INDIVIDUAL" className="mt-6">
          <div className="grid gap-4">
            {REQUIRED_DOCUMENTS.map((docType) => {
              const docs = getDocumentsForType(docType);
              const hasDocuments = docs.length > 0;
              const sample = SAMPLE_DOCUMENTS[docType];

              return (
                <Card
                  key={docType}
                  className={cn("transition-colors", hasDocuments && "border-primary/30")}
                >
                  <CardHeader className="pb-3">
                    <div className="flex items-center justify-between gap-2">
                      <CardTitle className="text-base font-medium">
                        {DOCUMENT_TYPE_LABELS[docType]}
                      </CardTitle>
                      <div className="flex items-center gap-2">
                        {hasDocuments && (
                          <Badge variant="secondary" className="text-xs">
                            {docs.length} file{docs.length > 1 ? "s" : ""}
                          </Badge>
                        )}
                        {sample && (
                          <Button
                            variant="outline"
                            size="sm"
                            className="h-7 gap-1.5 text-xs"
                            onClick={() => handleUseSample(docType)}
                          >
                            <Sparkles className="h-3 w-3" />
                            Use sample
                          </Button>
                        )}
                      </div>
                    </div>
                  </CardHeader>
                  <CardContent>
                    {hasDocuments ? (
                      <div className="space-y-2">
                        {docs.map((doc) => {
                          const statusConfig = STATUS_CONFIG[doc.status];
                          const StatusIcon = statusConfig.icon;
                          return (
                            <div
                              key={doc.file_id}
                              className="flex items-center justify-between p-3 bg-muted/50 rounded-lg"
                            >
                              <div className="flex items-center gap-3 min-w-0">
                                <FileText className="h-4 w-4 text-muted-foreground shrink-0" />
                                <span className="text-sm font-medium truncate">{doc.filename}</span>
                              </div>
                              <div className="flex items-center gap-3 shrink-0">
                                <DocumentVerificationBadge result={doc.verification} />
                                <div
                                  className={cn(
                                    "flex items-center gap-1.5 text-xs",
                                    statusConfig.className
                                  )}
                                >
                                  <StatusIcon className="h-3.5 w-3.5" />
                                  <span>{statusConfig.label}</span>
                                </div>
                                <Button
                                  variant="ghost"
                                  size="sm"
                                  className="h-7 gap-1.5 text-xs"
                                  onClick={() => setPreviewDoc({ docType, filename: doc.filename })}
                                >
                                  <Eye className="h-3.5 w-3.5" />
                                  Preview
                                </Button>
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    ) : (
                      <div className="border-2 border-dashed border-border rounded-lg p-6 text-center hover:border-primary/50 hover:bg-muted/30 transition-colors cursor-pointer">
                        <Upload className="h-8 w-8 mx-auto text-muted-foreground mb-2" />
                        <p className="text-sm text-muted-foreground">
                          Drag & drop or click to upload
                        </p>
                        <p className="text-xs text-muted-foreground mt-1">
                          PDF, JPG, PNG up to 10MB
                        </p>
                      </div>
                    )}
                  </CardContent>
                </Card>
              );
            })}

            <Card>
              <CardHeader className="pb-3">
                <CardTitle className="text-base font-medium">
                  {DOCUMENT_TYPE_LABELS.OTHER}
                </CardTitle>
                <CardDescription>Upload any additional supporting documents</CardDescription>
              </CardHeader>
              <CardContent>
                <div className="border-2 border-dashed border-border rounded-lg p-6 text-center hover:border-primary/50 hover:bg-muted/30 transition-colors cursor-pointer">
                  <Upload className="h-8 w-8 mx-auto text-muted-foreground mb-2" />
                  <p className="text-sm text-muted-foreground">Drag & drop or click to upload</p>
                </div>
              </CardContent>
            </Card>
          </div>
        </TabsContent>
      </Tabs>

      <DocumentPreviewModal
        open={!!previewDoc}
        onOpenChange={(o) => !o && setPreviewDoc(null)}
        docType={previewDoc?.docType ?? null}
        filename={previewDoc?.filename}
      />
    </div>
  );
}
