import type {
  AccountHolderResponse,
  KycRequirementResponse,
  LegalEntityAddressRequest,
  LegalEntityIdentificationRequest,
  LegalEntityResponse,
} from "@atomic-fi/sdk";
import {
  atomicFiApiAccountHolderControllerCreate,
  atomicFiApiAccountHolderControllerShow,
  atomicFiApiDocumentControllerCreate,
  atomicFiApiKycRequirementControllerCreate,
  atomicFiApiKycRequirementControllerShow,
  atomicFiApiSessionControllerVerify,
  buildApiKeySdk,
} from "@atomic-fi/sdk";
import type { Application, DocumentType } from "./types";

// ── Connection ──────────────────────────────────────────────────────
// The onboarding app holds no build-time credentials. The user supplies
// a backend API key at the ConnectGate; it is verified against
// GET /api/sessions/verify, then kept in sessionStorage for the rest of
// the browser tab's session. The tenant is whatever that session
// resolves to — derived from the API key server-side, never baked in.

const API_KEY_STORAGE_KEY = "atomic-fi:onboarding:api-key";

let tenantIdPromise: Promise<string> | undefined;

/** The API key stored for this browser session, or `null` if not connected. */
export function getStoredApiKey(): string | null {
  return sessionStorage.getItem(API_KEY_STORAGE_KEY);
}

function verifySession(): Promise<string> {
  return atomicFiApiSessionControllerVerify().then((res) => {
    if (res.error || !res.data) throw new Error("Invalid API key");
    const tenantId = (res.data as unknown as { tenant_id?: string }).tenant_id;
    if (!tenantId) throw new Error("Session response is missing tenant_id");
    return tenantId;
  });
}

/** Point the SDK at `apiKey` and (re)start tenant resolution. */
function activate(apiKey: string): void {
  buildApiKeySdk("", apiKey);
  tenantIdPromise = verifySession();
}

/**
 * Connect with an API key entered at the gate. Verifies it against
 * GET /api/sessions/verify; on success persists it for the rest of the
 * browser session. Throws if the key is invalid.
 */
export async function connectWithApiKey(apiKey: string): Promise<void> {
  const trimmed = apiKey.trim();
  if (!trimmed) throw new Error("API key is required");
  activate(trimmed);
  await tenantIdPromise; // surfaces an invalid key here, at the gate
  sessionStorage.setItem(API_KEY_STORAGE_KEY, trimmed);
}

function resolveTenantId(): Promise<string> {
  if (!tenantIdPromise) {
    const key = getStoredApiKey();
    if (!key) return Promise.reject(new Error("Not connected — enter an API key"));
    activate(key);
  }
  return tenantIdPromise as Promise<string>;
}

// Reconfigure the SDK on load if a key was stored earlier this session,
// so a page reload within the tab doesn't drop the connection.
const initialKey = getStoredApiKey();
if (initialKey) activate(initialKey);

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
  const tenantId = await resolveTenantId();

  const entityType = app.business_profile.entity_type ?? "";
  const holderType = HOLDER_TYPE_MAP[entityType] ?? "business";
  const legalStructure = LEGAL_STRUCTURE_MAP[entityType];
  const isIndividual = holderType === "individual";

  // Step 1: Create AccountHolder with nested LegalEntity (atomic)
  const ahRes = await atomicFiApiAccountHolderControllerCreate({
    body: {
      account_holder_type: holderType,
      status: "pending",
      kyc_status: "not_started",
      risk_level: "low",
      enabled_currencies: ["USD"],
      chain_screening: false,
      tenant_id: tenantId,
      legal_entity: {
        legal_entity_type: isIndividual ? "individual" : "business",
        business_name: app.business_profile.legal_name,
        doing_business_as_names: app.business_profile.trade_name
          ? [app.business_profile.trade_name]
          : undefined,
        date_formed: app.business_profile.incorporation_date || undefined,
        citizenship_country: "AE",
        legal_structure: legalStructure,
        tenant_id: tenantId,
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
        primary: true,
        status: "submitted",
        tenant_id: tenantId,
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
      tenant_id: tenantId,
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

export type SubmissionDetails = {
  accountHolder: AccountHolderResponse;
  legalEntity: LegalEntityResponse;
  kycRequirement: KycRequirementResponse;
};

export async function fetchSubmissionDetails(
  result: OnboardingResult,
): Promise<SubmissionDetails | null> {
  if (!getStoredApiKey()) return null;

  // LegalEntity has no standalone GET endpoint — all PII lives on the LE,
  // which is reached via the readOnly `legal_entity` object preloaded on
  // the AccountHolder response. So we fetch AH + KYC and pull the LE out
  // of the AH payload.
  const [ahRes, kycRes] = await Promise.all([
    atomicFiApiAccountHolderControllerShow({ path: { id: result.accountHolderId } }),
    atomicFiApiKycRequirementControllerShow({ path: { id: result.kycRequirementId } }),
  ]);

  if (ahRes.error || kycRes.error) return null;

  const accountHolder = ahRes.data as unknown as AccountHolderResponse;
  const legalEntity = (accountHolder as { legal_entity?: LegalEntityResponse })
    .legal_entity;

  if (!legalEntity) return null;

  return {
    accountHolder,
    legalEntity,
    kycRequirement: kycRes.data as unknown as KycRequirementResponse,
  };
}
