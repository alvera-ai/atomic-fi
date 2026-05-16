import bankStatement from "@/assets/samples/bank-statement.png";
import emiratesId from "@/assets/samples/emirates-id.png";
import incorporation from "@/assets/samples/incorporation.png";
import moa from "@/assets/samples/moa.png";
import passport from "@/assets/samples/passport.png";
import proofOfAddress from "@/assets/samples/proof-of-address.png";
import tradeLicense from "@/assets/samples/trade-license.png";
import type { Application, Document, DocumentType, FieldProvenance } from "@/types/onboarding";

export interface SampleDocument {
  doc_type: DocumentType;
  filename: string;
  imageUrl: string;
  /** Mutations applied to the application when this sample is loaded. */
  applyPrefill: (app: Application) => Partial<Application>;
  /** Provenance entries keyed by field path. */
  provenance: Record<string, FieldProvenance>;
}

export const SAMPLE_IMAGES: Partial<Record<DocumentType, string>> = {
  TRADE_LICENSE: tradeLicense,
  MEMORANDUM_OF_ASSOCIATION: moa,
  CERTIFICATE_OF_INCORPORATION: incorporation,
  PASSPORT: passport,
  EMIRATES_ID: emiratesId,
  PROOF_OF_ADDRESS: proofOfAddress,
  BANK_STATEMENT: bankStatement,
};

const now = () => new Date().toISOString();
const fileId = (prefix: string) =>
  `${prefix}-${Math.random().toString(36).slice(2, 8).toUpperCase()}`;

const conf = (
  source_doc_type: DocumentType,
  page_number: number,
  confidence: number,
  snippet: string,
): FieldProvenance => ({ source_doc_type, page_number, confidence, snippet });

export const SAMPLE_DOCUMENTS: Record<DocumentType, SampleDocument | null> = {
  TRADE_LICENSE: {
    doc_type: "TRADE_LICENSE",
    filename: "trade-license-falcon-crypto.png",
    imageUrl: tradeLicense,
    provenance: {
      "business_profile.legal_name": conf(
        "TRADE_LICENSE",
        1,
        98,
        "Falcon Crypto Trading Limited Liability Company",
      ),
      "business_profile.trade_name": conf("TRADE_LICENSE", 1, 97, "Falcon Crypto Trading LLC"),
      "business_profile.license_number": conf("TRADE_LICENSE", 1, 99, "License No: 1234567"),
      "business_profile.license_expiry": conf("TRADE_LICENSE", 1, 96, "Expiry Date: 14/03/2026"),
      "business_profile.jurisdiction": conf("TRADE_LICENSE", 1, 92, "Government of Dubai - DED"),
      "business_profile.entity_type": conf(
        "TRADE_LICENSE",
        1,
        94,
        "Legal Form: Limited Liability Company",
      ),
    },
    applyPrefill: (app) => ({
      business_profile: {
        ...app.business_profile,
        legal_name: "Falcon Crypto Trading LLC",
        trade_name: "Falcon Crypto",
        license_number: "1234567",
        license_expiry: "2026-03-14",
        jurisdiction: "dubai_mainland",
        entity_type: "llc",
      },
    }),
  },
  MEMORANDUM_OF_ASSOCIATION: {
    doc_type: "MEMORANDUM_OF_ASSOCIATION",
    filename: "moa-falcon-crypto.png",
    imageUrl: moa,
    provenance: {
      "ownership_structure.parent_company_name": conf(
        "MEMORANDUM_OF_ASSOCIATION",
        1,
        88,
        "Share Capital: AED 300,000 / 300 shares",
      ),
      "ubos[0].full_name": conf("MEMORANDUM_OF_ASSOCIATION", 1, 96, "Ahmed Al Mansouri 60%"),
      "ubos[1].full_name": conf("MEMORANDUM_OF_ASSOCIATION", 1, 95, "Sarah Khan 40%"),
    },
    applyPrefill: (app) => ({
      ownership_structure: {
        ...app.ownership_structure,
        is_subsidiary: false,
      },
      ubos:
        app.ubos.length > 0
          ? app.ubos
          : [
              {
                id: `ubo-${Math.random().toString(36).slice(2, 8)}`,
                full_name: "Ahmed Mohammed Al Mansouri",
                nationality: "United Arab Emirates",
                date_of_birth: "1985-06-12",
                ownership_percentage: 60,
                passport_number: "A12345678",
                residential_address:
                  "Apartment 2105, Marina Heights Tower, Dubai Marina, Dubai, UAE",
              },
              {
                id: `ubo-${Math.random().toString(36).slice(2, 8)}`,
                full_name: "Sarah Khan",
                nationality: "United Arab Emirates",
                date_of_birth: "1988-09-22",
                ownership_percentage: 40,
                passport_number: "B98765432",
                residential_address: "Villa 14, Al Barsha South, Dubai, UAE",
              },
            ],
    }),
  },
  CERTIFICATE_OF_INCORPORATION: {
    doc_type: "CERTIFICATE_OF_INCORPORATION",
    filename: "certificate-of-incorporation.png",
    imageUrl: incorporation,
    provenance: {
      "business_profile.incorporation_date": conf(
        "CERTIFICATE_OF_INCORPORATION",
        1,
        97,
        "incorporated on the 15th day of March 2023",
      ),
    },
    applyPrefill: (app) => ({
      business_profile: {
        ...app.business_profile,
        incorporation_date: "2023-03-15",
      },
    }),
  },
  PASSPORT: {
    doc_type: "PASSPORT",
    filename: "passport-ahmed-al-mansouri.png",
    imageUrl: passport,
    provenance: {
      "directors[0].full_name": conf("PASSPORT", 1, 99, "AHMED MOHAMMED AL MANSOURI"),
      "directors[0].nationality": conf("PASSPORT", 1, 98, "UNITED ARAB EMIRATES"),
      "directors[0].date_of_birth": conf("PASSPORT", 1, 97, "12 JUN 1985"),
      "directors[0].passport_number": conf("PASSPORT", 1, 99, "A12345678"),
    },
    applyPrefill: (app) => ({
      directors:
        app.directors.length > 0
          ? app.directors
          : [
              {
                id: `dir-${Math.random().toString(36).slice(2, 8)}`,
                full_name: "Ahmed Mohammed Al Mansouri",
                nationality: "United Arab Emirates",
                date_of_birth: "1985-06-12",
                passport_number: "A12345678",
                email: "ahmed@falconcrypto.ae",
                phone: "+971 50 123 4567",
                is_signatory: true,
              },
            ],
    }),
  },
  EMIRATES_ID: {
    doc_type: "EMIRATES_ID",
    filename: "emirates-id-ahmed.png",
    imageUrl: emiratesId,
    provenance: {
      "directors[0].emirates_id": conf("EMIRATES_ID", 1, 98, "784-1985-1234567-1"),
    },
    applyPrefill: (app) => ({
      // Emirates ID confirms the same person; no extra prefill needed beyond directors.
      directors: app.directors,
    }),
  },
  PROOF_OF_ADDRESS: {
    doc_type: "PROOF_OF_ADDRESS",
    filename: "dewa-bill-proof-of-address.png",
    imageUrl: proofOfAddress,
    provenance: {
      "addresses[0].line1": conf("PROOF_OF_ADDRESS", 1, 93, "Apartment 2105, Marina Heights Tower"),
      "addresses[0].city": conf("PROOF_OF_ADDRESS", 1, 95, "Dubai Marina"),
    },
    applyPrefill: (app) => ({
      addresses:
        app.addresses.length > 0
          ? app.addresses
          : [
              {
                id: `addr-${Math.random().toString(36).slice(2, 8)}`,
                type: "REGISTERED",
                line1: "Office 1204, Emirates Towers",
                line2: "Sheikh Zayed Road",
                city: "Dubai",
                emirate: "Dubai",
                country: "United Arab Emirates",
                postal_code: "00000",
              },
              {
                id: `addr-${Math.random().toString(36).slice(2, 8)}`,
                type: "CORRESPONDENCE",
                line1: "Apartment 2105, Marina Heights Tower",
                line2: "Dubai Marina",
                city: "Dubai",
                emirate: "Dubai",
                country: "United Arab Emirates",
              },
            ],
    }),
  },
  BANK_STATEMENT: {
    doc_type: "BANK_STATEMENT",
    filename: "emirates-nbd-statement-q1-2026.png",
    imageUrl: bankStatement,
    provenance: {
      "transfer_behavior.expected_monthly_volume_usd": conf(
        "BANK_STATEMENT",
        1,
        85,
        "Closing balance AED 612,300",
      ),
    },
    applyPrefill: (app) => ({
      transfer_behavior: {
        ...app.transfer_behavior,
        expected_monthly_volume_usd: 165000,
        expected_monthly_transactions: 45,
        primary_transfer_purpose: "Operating expenses & vendor payments",
      },
    }),
  },
  OTHER: null,
};

export function buildSampleDocument(sample: SampleDocument): Document {
  // Demo: most pass, bank statement gets a WARN to demonstrate the UI
  const verification =
    sample.doc_type === "BANK_STATEMENT"
      ? {
          status: "WARN" as const,
          flags: ["FAKE_SUSPECTED" as const],
          message: "Statement metadata couldn't be cross-checked — manual review suggested",
        }
      : { status: "PASS" as const, flags: [], message: "Verified" };

  return {
    file_id: fileId("file"),
    doc_type: sample.doc_type,
    filename: sample.filename,
    status: "EXTRACTED",
    uploaded_at: now(),
    verification,
  };
}
