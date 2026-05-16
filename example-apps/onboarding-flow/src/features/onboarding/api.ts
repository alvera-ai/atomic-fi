import type { LegalEntityAddressRequest, LegalEntityIdentificationRequest } from "@atomic-fi/sdk";
import {
  atomicFiApiAccountHolderControllerCreate,
  atomicFiApiDocumentControllerCreate,
  atomicFiApiKycRequirementControllerCreate,
  buildApiKeySdk,
} from "@atomic-fi/sdk";
import type { Application, DocumentType } from "./types";

const API_KEY = import.meta.env.VITE_API_KEY as string;
const TENANT_ID = import.meta.env.VITE_TENANT_ID as string;

if (API_KEY) {
  buildApiKeySdk("", API_KEY);
}

const DOCUMENT_TYPE_MAP: Record<
  DocumentType,
  "identity_document" | "proof_of_address" | "source_of_funds" | "business_registration" | "other"
> = {
  TRADE_LICENSE: "business_registration",
  MEMORANDUM_OF_ASSOCIATION: "business_registration",
  CERTIFICATE_OF_INCORPORATION: "business_registration",
  PASSPORT: "identity_document",
  EMIRATES_ID: "identity_document",
  PROOF_OF_ADDRESS: "proof_of_address",
  BANK_STATEMENT: "source_of_funds",
  OTHER: "other",
};

const HOLDER_TYPE_MAP: Record<string, "individual" | "business" | "trust" | "nonprofit"> = {
  llc: "business",
  sole_prop: "individual",
  branch: "business",
  fze: "business",
  fzco: "business",
};

const LEGAL_STRUCTURE_MAP: Record<
  string,
  "corporation" | "llc" | "sole_proprietorship" | "partnership" | "trust" | "non_profit"
> = {
  llc: "llc",
  sole_prop: "sole_proprietorship",
  branch: "corporation",
  fze: "corporation",
  fzco: "corporation",
};

export type OnboardingResult = {
  accountHolderId: string;
  legalEntityId: string;
  documentIds: string[];
  kycRequirementId: string;
};

type ApiResponse = { id: string; legal_entity_id?: string };

function mapAddresses(app: Application): LegalEntityAddressRequest[] {
  return app.addresses.map((addr) => ({
    address_types: ["business" as const],
    line1: addr.line1,
    line2: addr.line2,
    locality: addr.city,
    region: addr.emirate,
    country: addr.country,
    postal_code: addr.postal_code,
    primary: addr.type === "REGISTERED",
  }));
}

function mapIdentifications(app: Application): LegalEntityIdentificationRequest[] {
  const seen = new Set<string>();
  const ids: LegalEntityIdentificationRequest[] = [];

  for (const person of [...app.directors, ...app.ubos]) {
    if (person.passport_number && !seen.has("passport")) {
      seen.add("passport");
      ids.push({
        id_type: "passport",
        id_number: person.passport_number,
        issuing_country: person.nationality || undefined,
      });
    }
  }

  return ids;
}

export async function submitOnboarding(app: Application): Promise<OnboardingResult> {
  if (!API_KEY) throw new Error("VITE_API_KEY is not configured");
  if (!TENANT_ID) throw new Error("VITE_TENANT_ID is not configured");

  const entityType = app.business_profile.entity_type ?? "";
  const holderType = HOLDER_TYPE_MAP[entityType] ?? "business";
  const legalStructure = LEGAL_STRUCTURE_MAP[entityType];
  const isIndividual = holderType === "individual";

  // Step 1: Create AccountHolder with nested LegalEntity (atomic)
  const ahRes = await atomicFiApiAccountHolderControllerCreate({
    body: {
      holder_type: holderType,
      status: "pending",
      kyc_status: "not_started",
      risk_level: "low",
      enabled_currencies: ["USD"],
      chain_screening: false,
      tenant_id: TENANT_ID,
      legal_entity: {
        legal_entity_type: isIndividual ? "individual" : "business",
        business_name: app.business_profile.legal_name,
        doing_business_as_names: app.business_profile.trade_name
          ? [app.business_profile.trade_name]
          : undefined,
        date_formed: app.business_profile.incorporation_date || undefined,
        citizenship_country: "AE",
        legal_structure: legalStructure,
        tenant_id: TENANT_ID,
        addresses: mapAddresses(app),
        identifications: mapIdentifications(app),
      },
    },
  });

  if (ahRes.error) {
    throw new Error(`Failed to create AccountHolder: ${JSON.stringify(ahRes.error)}`);
  }

  const ahBody = ahRes.data as unknown as ApiResponse;
  const accountHolderId = ahBody.id;
  const legalEntityId = ahBody.legal_entity_id ?? "";

  // Step 2: Create Documents for each uploaded doc
  const documentIds: string[] = [];
  for (const doc of app.documents) {
    const docRes = await atomicFiApiDocumentControllerCreate({
      body: {
        account_holder_id: accountHolderId,
        document_type: DOCUMENT_TYPE_MAP[doc.doc_type],
        name: doc.doc_type.toLowerCase(),
        file_name: doc.filename,
        primary: documentIds.length === 0,
        status: "submitted",
        tenant_id: TENANT_ID,
      },
    });

    if (docRes.error) {
      throw new Error(`Failed to create Document: ${JSON.stringify(docRes.error)}`);
    }

    const docBody = docRes.data as unknown as ApiResponse;
    documentIds.push(docBody.id);
  }

  // Step 3: Create KycRequirement for AH scope
  const kycRes = await atomicFiApiKycRequirementControllerCreate({
    body: {
      account_holder_id: accountHolderId,
      legal_entity_id: legalEntityId,
      scope: "account_holder",
      requirement_type: "identity_document",
      status: "submitted",
      document_id: documentIds[0],
      tenant_id: TENANT_ID,
    },
  });

  if (kycRes.error) {
    throw new Error(`Failed to create KycRequirement: ${JSON.stringify(kycRes.error)}`);
  }

  const kycBody = kycRes.data as unknown as ApiResponse;

  return {
    accountHolderId,
    legalEntityId,
    documentIds,
    kycRequirementId: kycBody.id,
  };
}
