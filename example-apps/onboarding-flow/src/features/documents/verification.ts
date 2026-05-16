import type {
  DocumentType,
  VerificationFlag,
  VerificationResult,
} from "@/features/onboarding/types";
import { classifyFilename } from "./classifier";

const ACCEPTED_MIME = ["application/pdf", "image/png", "image/jpeg", "image/jpg"];
const SUSPICIOUS = /\b(test|dummy|fake|copy|untitled|screenshot|img_\d+)\b/i;

interface VerifyOptions {
  /** The slot/category the user (or classifier) assigned to this file. */
  expectedType: DocumentType;
  /** When true, skip heuristic checks (e.g. for bundled sample mocks). */
  trusted?: boolean;
}

export async function verifyDocument(
  file: File,
  { expectedType, trusted }: VerifyOptions,
): Promise<VerificationResult> {
  if (trusted) {
    return { status: "PASS", flags: [], message: "Verified" };
  }

  const flags: VerificationFlag[] = [];

  // Wrong format → hard fail
  if (file.type && !ACCEPTED_MIME.includes(file.type)) {
    flags.push("WRONG_FORMAT");
    return {
      status: "FAIL",
      flags,
      message: `Unsupported file type (${file.type || "unknown"}). Use PDF, JPG or PNG.`,
    };
  }

  // Illegible: too small
  if (file.size < 1024) {
    flags.push("ILLEGIBLE");
  }

  // Suspicious filename
  if (SUSPICIOUS.test(file.name)) {
    flags.push("FAKE_SUSPECTED");
  }

  // Filename / type mismatch
  const detected = classifyFilename(file.name);
  if (
    expectedType !== "OTHER" &&
    detected.docType !== "OTHER" &&
    detected.docType !== expectedType
  ) {
    flags.push("IRRELEVANT");
  }

  // Image dimension check (best-effort)
  if (file.type.startsWith("image/")) {
    const dims = await readImageDimensions(file).catch(() => null);
    if (dims && (dims.width < 600 || dims.height < 600)) {
      if (!flags.includes("ILLEGIBLE")) flags.push("ILLEGIBLE");
    }
  }

  if (flags.length === 0) {
    return { status: "PASS", flags, message: "Verified" };
  }

  const status: VerificationResult["status"] = flags.includes("ILLEGIBLE") ? "FAIL" : "WARN";
  return { status, flags, message: describeFlags(flags) };
}

function describeFlags(flags: VerificationFlag[]): string {
  return flags.map((f) => FLAG_LABELS[f]).join(" • ");
}

export const FLAG_LABELS: Record<VerificationFlag, string> = {
  ILLEGIBLE: "Document appears illegible or low-resolution",
  FAKE_SUSPECTED: "Filename looks suspicious — verify authenticity",
  IRRELEVANT: "File doesn't match the expected document type",
  WRONG_FORMAT: "Unsupported file format",
  EXPIRED: "Document appears to be expired",
};

function readImageDimensions(file: File): Promise<{ width: number; height: number }> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      resolve({ width: img.naturalWidth, height: img.naturalHeight });
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("image load failed"));
    };
    img.src = url;
  });
}

export function summarizeVerification(results: Array<VerificationResult | undefined>): {
  fail: number;
  warn: number;
  pass: number;
} {
  const out = { fail: 0, warn: 0, pass: 0 };
  for (const r of results) {
    if (!r) continue;
    if (r.status === "FAIL") out.fail++;
    else if (r.status === "WARN") out.warn++;
    else out.pass++;
  }
  return out;
}
