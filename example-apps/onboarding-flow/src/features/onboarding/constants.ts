import type { DocumentType, StepDefinition } from "./types";

export const ONBOARDING_STEPS: StepDefinition[] = [
  {
    id: 1,
    title: "Upload documents",
    path: "documents",
    description: "Upload required business documents",
  },
  {
    id: 2,
    title: "Business identity",
    path: "identity",
    description: "Basic business information",
  },
  {
    id: 3,
    title: "Addresses",
    path: "addresses",
    description: "Registered and operating addresses",
  },
  { id: 4, title: "Business contacts", path: "contacts", description: "Key contact persons" },
  {
    id: 5,
    title: "Business activity & purpose",
    path: "activity",
    description: "Nature of business operations",
  },
  {
    id: 6,
    title: "Expected transfer behavior",
    path: "transfers",
    description: "UAE to US transfer patterns",
  },
  {
    id: 7,
    title: "Ownership structure",
    path: "ownership",
    description: "Company ownership details",
  },
  {
    id: 8,
    title: "Directors & signatories",
    path: "directors",
    description: "Key decision makers",
  },
  { id: 9, title: "UBOs", path: "ubos", description: "Ultimate beneficial owners" },
  { id: 10, title: "Review & submit", path: "review", description: "Final review and submission" },
];

// Document type labels
export const DOCUMENT_TYPE_LABELS: Record<DocumentType, string> = {
  TRADE_LICENSE: "Trade License",
  MEMORANDUM_OF_ASSOCIATION: "Memorandum of Association",
  CERTIFICATE_OF_INCORPORATION: "Certificate of Incorporation",
  PASSPORT: "Passport (Authorized Signatory)",
  EMIRATES_ID: "Emirates ID",
  PROOF_OF_ADDRESS: "Proof of Address",
  BANK_STATEMENT: "Bank Statement",
  OTHER: "Other Documents",
};
