import type { DocumentType } from "@/features/onboarding/types";

export interface ClassificationResult {
  docType: DocumentType;
  confidence: number; // 0..1
}

// Keyword groups (longer / more specific first)
const RULES: Array<{ type: DocumentType; patterns: RegExp[]; strong: RegExp[] }> = [
  {
    type: "MEMORANDUM_OF_ASSOCIATION",
    strong: [/\bmoa\b/, /memorandum/],
    patterns: [/articles[-_ ]?of[-_ ]?association/, /\baoa\b/],
  },
  {
    type: "CERTIFICATE_OF_INCORPORATION",
    strong: [/\bcoi\b/, /incorporation/, /certificate[-_ ]?of[-_ ]?incorp/],
    patterns: [/\bcert\b/],
  },
  {
    type: "TRADE_LICENSE",
    strong: [/trade[-_ ]?license/, /\btrade[-_ ]?lic\b/, /\btl\b/],
    patterns: [/license/],
  },
  {
    type: "EMIRATES_ID",
    strong: [/emirates[-_ ]?id/, /\beid\b/],
    patterns: [/\bid[-_ ]?card\b/],
  },
  {
    type: "PASSPORT",
    strong: [/passport/, /\bpp\b/],
    patterns: [],
  },
  {
    type: "PROOF_OF_ADDRESS",
    strong: [/proof[-_ ]?of[-_ ]?address/, /\bpoa\b/, /utility[-_ ]?bill/],
    patterns: [/address/, /utility/],
  },
  {
    type: "BANK_STATEMENT",
    strong: [/bank[-_ ]?statement/, /\bstatement\b/],
    patterns: [/\bbank\b/],
  },
];

export function classifyFilename(filename: string): ClassificationResult {
  const name = filename.toLowerCase().replace(/\.[a-z0-9]+$/, "");
  for (const rule of RULES) {
    if (rule.strong.some((re) => re.test(name))) {
      return { docType: rule.type, confidence: 0.95 };
    }
  }
  for (const rule of RULES) {
    if (rule.patterns.some((re) => re.test(name))) {
      return { docType: rule.type, confidence: 0.6 };
    }
  }
  return { docType: "OTHER", confidence: 0 };
}
