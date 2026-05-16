import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { ScrollArea } from "@/components/ui/scroll-area";
import { SAMPLE_IMAGES } from "@/features/documents/samples";
import { DOCUMENT_TYPE_LABELS } from "@/features/onboarding/constants";
import type { DocumentType } from "@/features/onboarding/types";

interface DocumentPreviewModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  docType: DocumentType | null;
  filename?: string;
}

export function DocumentPreviewModal({
  open,
  onOpenChange,
  docType,
  filename,
}: DocumentPreviewModalProps) {
  const imageUrl = docType ? SAMPLE_IMAGES[docType] : undefined;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[90vh] p-0 gap-0">
        <DialogHeader className="px-6 py-4 border-b border-border">
          <DialogTitle>{docType ? DOCUMENT_TYPE_LABELS[docType] : "Document"}</DialogTitle>
          {filename && <DialogDescription className="text-xs">{filename}</DialogDescription>}
        </DialogHeader>
        <ScrollArea className="max-h-[75vh]">
          <div className="p-6 bg-muted/30 flex justify-center">
            {imageUrl ? (
              <img
                src={imageUrl}
                alt={docType ? DOCUMENT_TYPE_LABELS[docType] : "Document preview"}
                className="max-w-full h-auto rounded-md shadow-lg border border-border"
                loading="lazy"
              />
            ) : (
              <div className="py-12 text-sm text-muted-foreground">No preview available</div>
            )}
          </div>
        </ScrollArea>
      </DialogContent>
    </Dialog>
  );
}
