import { useRef, useState } from "react";
import { Upload, Trash2, Sparkles, Info, FileText } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { cn } from "@/lib/utils";
import { toast } from "sonner";
import {
  Application,
  Document,
  DocumentType,
  DOCUMENT_TYPE_LABELS,
  VerificationResult,
} from "@/types/onboarding";
import { classifyFilename } from "@/lib/documentClassifier";
import { verifyDocument } from "@/lib/documentVerification";
import { DocumentVerificationBadge } from "./DocumentVerificationBadge";
import { SAMPLE_DOCUMENTS, buildSampleDocument } from "@/data/sampleDocuments";

interface PendingFile {
  id: string;
  file?: File; // absent for "load samples" entries
  filename: string;
  detectedType: DocumentType;
  confidence: number;
  verification?: VerificationResult;
  verifying: boolean;
  trusted?: boolean;
}

interface Props {
  application: Application;
  updateApplication: (u: Partial<Application>) => void;
}

const DOC_TYPE_OPTIONS: DocumentType[] = [
  "TRADE_LICENSE",
  "MEMORANDUM_OF_ASSOCIATION",
  "CERTIFICATE_OF_INCORPORATION",
  "PASSPORT",
  "EMIRATES_ID",
  "PROOF_OF_ADDRESS",
  "BANK_STATEMENT",
  "OTHER",
];

export function BulkUploadZone({ application, updateApplication }: Props) {
  const [pending, setPending] = useState<PendingFile[]>([]);
  const [dragOver, setDragOver] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const addFiles = async (files: File[]) => {
    const newEntries: PendingFile[] = files.map((f) => {
      const cls = classifyFilename(f.name);
      return {
        id: `${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
        file: f,
        filename: f.name,
        detectedType: cls.docType,
        confidence: cls.confidence,
        verifying: true,
      };
    });
    setPending((p) => [...p, ...newEntries]);

    // verify async
    for (const entry of newEntries) {
      if (!entry.file) continue;
      const result = await verifyDocument(entry.file, { expectedType: entry.detectedType });
      setPending((p) =>
        p.map((x) => (x.id === entry.id ? { ...x, verification: result, verifying: false } : x))
      );
    }
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setDragOver(false);
    addFiles(Array.from(e.dataTransfer.files));
  };

  const onPickFiles = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files) addFiles(Array.from(e.target.files));
    e.target.value = "";
  };

  const updateType = async (id: string, docType: DocumentType) => {
    setPending((p) => p.map((x) => (x.id === id ? { ...x, detectedType: docType, verifying: !!x.file } : x)));
    const entry = pending.find((x) => x.id === id);
    if (entry?.file) {
      const result = await verifyDocument(entry.file, { expectedType: docType, trusted: entry.trusted });
      setPending((p) =>
        p.map((x) => (x.id === id ? { ...x, verification: result, verifying: false } : x))
      );
    }
  };

  const removeEntry = (id: string) => setPending((p) => p.filter((x) => x.id !== id));

  const loadAllSamples = () => {
    const samples = Object.values(SAMPLE_DOCUMENTS).filter(Boolean) as NonNullable<
      (typeof SAMPLE_DOCUMENTS)[keyof typeof SAMPLE_DOCUMENTS]
    >[];
    const entries: PendingFile[] = samples.map((s) => ({
      id: `${Date.now()}-${s.doc_type}`,
      filename: s.filename,
      detectedType: s.doc_type,
      confidence: 1,
      trusted: true,
      verifying: false,
      verification:
        s.doc_type === "BANK_STATEMENT"
          ? {
              status: "WARN",
              flags: ["FAKE_SUSPECTED"],
              message: "Statement metadata couldn't be cross-checked",
            }
          : { status: "PASS", flags: [], message: "Verified" },
    }));
    setPending((p) => [...p, ...entries]);
    toast.success(`${entries.length} sample documents loaded`);
  };

  const processFiles = () => {
    if (pending.some((p) => p.verifying)) {
      toast.error("Verification still running…");
      return;
    }
    const blocking = pending.filter((p) => p.verification?.status === "FAIL");
    if (blocking.length > 0) {
      toast.error(`${blocking.length} file(s) failed verification — remove or replace them first`);
      return;
    }

    const newDocs: Document[] = [];
    let prefillUpdates: Partial<Application> = {};
    let provenance = { ...application.field_provenance };

    for (const entry of pending) {
      const sample = SAMPLE_DOCUMENTS[entry.detectedType];
      if (entry.trusted && sample) {
        newDocs.push(buildSampleDocument(sample));
        const partial = sample.applyPrefill({ ...application, ...prefillUpdates } as Application);
        prefillUpdates = { ...prefillUpdates, ...partial };
        provenance = { ...provenance, ...sample.provenance };
      } else {
        newDocs.push({
          file_id: `file-${Math.random().toString(36).slice(2, 8).toUpperCase()}`,
          doc_type: entry.detectedType,
          filename: entry.filename,
          status: entry.verification?.status === "WARN" ? "NEEDS_ATTENTION" : "EXTRACTED",
          uploaded_at: new Date().toISOString(),
          verification: entry.verification,
        });
      }
    }

    updateApplication({
      ...prefillUpdates,
      documents: [...application.documents, ...newDocs],
      field_provenance: provenance,
    });

    setPending([]);
    toast.success(`${newDocs.length} document(s) processed`, {
      description: "Categorized and prefilled where possible",
    });
  };

  const counts = pending.reduce(
    (acc, p) => {
      if (p.verification?.status === "FAIL") acc.fail++;
      else if (p.verification?.status === "WARN") acc.warn++;
      else if (p.verification?.status === "PASS") acc.pass++;
      return acc;
    },
    { pass: 0, warn: 0, fail: 0 }
  );

  return (
    <div className="space-y-4">
      <Alert>
        <Info className="h-4 w-4" />
        <AlertTitle>Naming guide for best auto-categorization</AlertTitle>
        <AlertDescription className="mt-2">
          <ul className="text-xs grid sm:grid-cols-2 gap-x-6 gap-y-1 font-mono">
            <li>trade-license_company.pdf → Trade License</li>
            <li>moa_company.pdf → Memorandum</li>
            <li>coi_company.pdf → Certificate of Incorporation</li>
            <li>passport_jane.pdf → Passport</li>
            <li>emirates-id_jane.pdf → Emirates ID</li>
            <li>proof-of-address_jane.pdf → Proof of Address</li>
            <li>bank-statement_2025-01.pdf → Bank Statement</li>
          </ul>
          <p className="text-xs mt-2 text-muted-foreground">
            Files that don't match a keyword will land in "Other" — you can re-categorize them below.
          </p>
        </AlertDescription>
      </Alert>

      <div
        className={cn(
          "border-2 border-dashed rounded-lg p-10 text-center transition-colors cursor-pointer",
          dragOver ? "border-primary bg-primary/5" : "border-border hover:border-primary/50 hover:bg-muted/30"
        )}
        onDragOver={(e) => {
          e.preventDefault();
          setDragOver(true);
        }}
        onDragLeave={() => setDragOver(false)}
        onDrop={handleDrop}
        onClick={() => inputRef.current?.click()}
      >
        <input
          ref={inputRef}
          type="file"
          multiple
          accept=".pdf,.png,.jpg,.jpeg"
          className="hidden"
          onChange={onPickFiles}
        />
        <Upload className="h-10 w-10 mx-auto text-muted-foreground mb-3" />
        <p className="text-sm font-medium">Drop all your documents here</p>
        <p className="text-xs text-muted-foreground mt-1">PDF, JPG, PNG up to 10MB each</p>
        <Button
          variant="outline"
          size="sm"
          className="mt-4 gap-1.5"
          onClick={(e) => {
            e.stopPropagation();
            loadAllSamples();
          }}
        >
          <Sparkles className="h-3.5 w-3.5" />
          Load all sample files
        </Button>
      </div>

      {pending.length > 0 && (
        <Card>
          <CardContent className="p-4 space-y-3">
            <div className="flex items-center justify-between">
              <div className="text-sm font-medium">
                {pending.length} file{pending.length > 1 ? "s" : ""} ready
                <span className="text-muted-foreground font-normal ml-2">
                  · {counts.pass} verified · {counts.warn} review · {counts.fail} blocked
                </span>
              </div>
              <div className="flex gap-2">
                <Button variant="ghost" size="sm" onClick={() => setPending([])}>
                  Clear
                </Button>
                <Button variant="secondary" size="sm" onClick={processFiles}>
                  Process files
                </Button>
              </div>
            </div>

            <div className="divide-y border rounded-md">
              {pending.map((p) => (
                <div key={p.id} className="flex items-center gap-3 p-3">
                  <FileText className="h-4 w-4 text-muted-foreground shrink-0" />
                  <div className="min-w-0 flex-1">
                    <div className="text-sm truncate">{p.filename}</div>
                    {p.confidence < 0.9 && (
                      <div className="text-[11px] text-amber-600 dark:text-amber-400 mt-0.5">
                        {p.confidence === 0
                          ? "Couldn't auto-categorize — pick a type"
                          : "Low-confidence match — please confirm"}
                      </div>
                    )}
                  </div>
                  <Select value={p.detectedType} onValueChange={(v) => updateType(p.id, v as DocumentType)}>
                    <SelectTrigger className="h-8 w-[220px] text-xs">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {DOC_TYPE_OPTIONS.map((t) => (
                        <SelectItem key={t} value={t} className="text-xs">
                          {DOCUMENT_TYPE_LABELS[t]}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <div className="w-32 text-right">
                    {p.verifying ? (
                      <span className="text-xs text-muted-foreground">Verifying…</span>
                    ) : (
                      <DocumentVerificationBadge result={p.verification} className="justify-end" />
                    )}
                  </div>
                  <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => removeEntry(p.id)}>
                    <Trash2 className="h-3.5 w-3.5" />
                  </Button>
                </div>
              ))}
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
