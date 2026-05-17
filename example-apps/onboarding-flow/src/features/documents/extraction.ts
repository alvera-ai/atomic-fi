import type { Application, DocumentType } from "@/features/onboarding/types";

type ServerDocType = "passport" | "national_id" | "bank_statement" | "memorandum" | "custom";

const DOC_TYPE_MAP: Record<DocumentType, ServerDocType> = {
  PASSPORT: "passport",
  EMIRATES_ID: "national_id",
  BANK_STATEMENT: "bank_statement",
  MEMORANDUM_OF_ASSOCIATION: "memorandum",
  TRADE_LICENSE: "custom",
  CERTIFICATE_OF_INCORPORATION: "custom",
  PROOF_OF_ADDRESS: "custom",
  OTHER: "custom",
};

const TRADE_LICENSE_SCHEMA = {
  type: "object",
  properties: {
    legal_name: { type: "string", description: "Full legal company name" },
    trade_name: { type: "string", description: "Trading name / DBA" },
    license_number: { type: "string", description: "License number" },
    license_expiry: { type: "string", description: "Expiry date YYYY-MM-DD" },
    jurisdiction: { type: "string", description: "Issuing authority / jurisdiction" },
    entity_type: { type: "string", description: "Legal form: llc, sole_prop, branch, fze, fzco" },
    activities: {
      type: "array",
      items: { type: "string" },
      description: "Licensed business activities",
    },
  },
};

const COI_SCHEMA = {
  type: "object",
  properties: {
    company_name: { type: "string", description: "Full legal company name" },
    incorporation_date: { type: "string", description: "Date of incorporation YYYY-MM-DD" },
    jurisdiction: { type: "string", description: "Jurisdiction of incorporation" },
    registration_number: { type: "string", description: "Registration / company number" },
  },
};

const POA_SCHEMA = {
  type: "object",
  properties: {
    line1: { type: "string", description: "Street address line 1" },
    line2: { type: "string", description: "Street address line 2" },
    city: { type: "string", description: "City" },
    emirate: { type: "string", description: "State / emirate / region" },
    country: { type: "string", description: "Country" },
    postal_code: { type: "string", description: "Postal / ZIP code" },
  },
};

const CUSTOM_SCHEMAS: Partial<Record<DocumentType, { schema: object; prompt: string }>> = {
  TRADE_LICENSE: {
    schema: TRADE_LICENSE_SCHEMA,
    prompt:
      "Extract all business license information from this trade license document. " +
      "entity_type should be one of: llc, sole_prop, branch, fze, fzco. " +
      "Dates in YYYY-MM-DD. Use null for fields not found.",
  },
  CERTIFICATE_OF_INCORPORATION: {
    schema: COI_SCHEMA,
    prompt:
      "Extract incorporation details from this certificate. Dates in YYYY-MM-DD. Use null for fields not found.",
  },
  PROOF_OF_ADDRESS: {
    schema: POA_SCHEMA,
    prompt:
      "Extract the address from this proof of address document (utility bill, bank letter, etc). Use null for fields not found.",
  },
};

interface ExtractionResult {
  filename: string;
  document_type: string;
  success: boolean;
  data: Record<string, unknown> | null;
  error: string | null;
  usage: { input_tokens: number; output_tokens: number; cost_usd: number } | null;
}

interface ExtractionResponse {
  results: ExtractionResult[];
}

export async function extractDocuments(
  files: File[],
  docTypes: DocumentType[],
): Promise<ExtractionResponse> {
  const formData = new FormData();
  const metadata = docTypes.map((dt) => {
    const serverType = DOC_TYPE_MAP[dt];
    const custom = CUSTOM_SCHEMAS[dt];
    if (serverType === "custom" && custom) {
      return { document_type: "custom", output_schema: custom.schema, prompt: custom.prompt };
    }
    return { document_type: serverType };
  });

  for (const file of files) {
    formData.append("files", file);
  }
  formData.append("metadata", JSON.stringify(metadata));

  const res = await fetch("/extract", { method: "POST", body: formData });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Extraction failed (${res.status}): ${text}`);
  }
  return res.json() as Promise<ExtractionResponse>;
}

// ---------------------------------------------------------------------------
// Mapping extraction results → Application partial updates
// ---------------------------------------------------------------------------

type PartialApp = Partial<Application>;

function randomId(prefix: string) {
  return `${prefix}-${Math.random().toString(36).slice(2, 8)}`;
}

function mapMemorandum(data: Record<string, unknown>, app: Application): PartialApp {
  const shareholders = data.shareholders as Array<Record<string, unknown>> | undefined;
  const directors = data.directors as Array<Record<string, unknown>> | undefined;
  const activities = data.business_activities as string[] | undefined;

  const updates: PartialApp = {};

  updates.business_profile = {
    ...app.business_profile,
    legal_name: (data.company_name as string) || app.business_profile.legal_name,
    incorporation_date:
      (data.date_of_formation as string) || app.business_profile.incorporation_date,
  };

  if ((data.registered_address as string) && app.addresses.length === 0) {
    updates.addresses = [
      {
        id: randomId("addr"),
        type: "REGISTERED",
        line1: data.registered_address as string,
        city: "",
        country: "AE",
      },
    ];
  }

  if (directors && directors.length > 0 && app.directors.length === 0) {
    updates.directors = directors.map((d) => ({
      id: randomId("dir"),
      full_name: (d.name as string) || "",
      nationality: (d.nationality as string) || "",
      date_of_birth: "",
      passport_number: "",
      email: "",
      phone: "",
      is_signatory: (d.role as string)?.toLowerCase().includes("chairman") ?? false,
    }));
  }

  if (shareholders && shareholders.length > 0 && app.ubos.length === 0) {
    updates.ubos = shareholders
      .filter((s) => (s.share_percentage as number) >= 10)
      .map((s) => ({
        id: randomId("ubo"),
        full_name: (s.name as string) || "",
        nationality: (s.nationality as string) || "",
        date_of_birth: "",
        ownership_percentage: (s.share_percentage as number) || 0,
        passport_number: "",
        residential_address: "",
      }));
  }

  if (activities && activities.length > 0) {
    updates.business_activity = {
      ...app.business_activity,
      primary_activity: activities[0],
      secondary_activities: activities.slice(1, 4),
    };
  }

  return updates;
}

function mapPassport(data: Record<string, unknown>, app: Application): PartialApp {
  const personal = data.personal_info as Record<string, unknown> | undefined;
  const docInfo = data.document_info as Record<string, unknown> | undefined;
  if (!personal) return {};

  const fullName =
    (personal.full_name as string) ||
    [personal.first_name, personal.last_name].filter(Boolean).join(" ");

  const existing = app.directors.find((d) => d.full_name.toLowerCase() === fullName.toLowerCase());

  if (existing) {
    return {
      directors: app.directors.map((d) =>
        d.id === existing.id
          ? {
              ...d,
              nationality: (personal.nationality as string) || d.nationality,
              date_of_birth: (personal.date_of_birth as string) || d.date_of_birth,
              passport_number: (docInfo?.id_number as string) || d.passport_number,
            }
          : d,
      ),
    };
  }

  if (app.directors.length === 0) {
    return {
      directors: [
        {
          id: randomId("dir"),
          full_name: fullName,
          nationality: (personal.nationality as string) || "",
          date_of_birth: (personal.date_of_birth as string) || "",
          passport_number: (docInfo?.id_number as string) || "",
          email: "",
          phone: (personal.phone as string) || "",
          is_signatory: true,
        },
      ],
    };
  }

  return {};
}

function mapNationalId(data: Record<string, unknown>, app: Application): PartialApp {
  const personal = data.personal_info as Record<string, unknown> | undefined;
  if (!personal) return {};

  const fullName =
    (personal.full_name as string) ||
    [personal.first_name, personal.last_name].filter(Boolean).join(" ");

  const existing = app.directors.find((d) => d.full_name.toLowerCase() === fullName.toLowerCase());

  if (existing && personal.address) {
    return {
      directors: app.directors.map((d) =>
        d.id === existing.id
          ? { ...d, nationality: (personal.nationality as string) || d.nationality }
          : d,
      ),
    };
  }

  return {};
}

function mapBankStatement(data: Record<string, unknown>, app: Application): PartialApp {
  const account = data.account as Record<string, unknown> | undefined;
  const totalCredits = data.total_credits as number | undefined;
  const totalDebits = data.total_debits as number | undefined;

  const updates: PartialApp = {};

  if (totalCredits || totalDebits) {
    updates.transfer_behavior = {
      ...app.transfer_behavior,
      expected_monthly_volume_usd: Math.round(totalCredits || totalDebits || 0),
      expected_monthly_transactions:
        (data.transactions as unknown[])?.length ||
        app.transfer_behavior.expected_monthly_transactions,
      primary_transfer_purpose:
        app.transfer_behavior.primary_transfer_purpose || "Operating expenses & vendor payments",
    };
  }

  if (account?.account_holder && !app.business_profile.legal_name) {
    updates.business_profile = {
      ...app.business_profile,
      legal_name: account.account_holder as string,
    };
  }

  return updates;
}

function mapTradeLicense(data: Record<string, unknown>, app: Application): PartialApp {
  return {
    business_profile: {
      ...app.business_profile,
      legal_name: (data.legal_name as string) || app.business_profile.legal_name,
      trade_name: (data.trade_name as string) || app.business_profile.trade_name,
      license_number: (data.license_number as string) || app.business_profile.license_number,
      license_expiry: (data.license_expiry as string) || app.business_profile.license_expiry,
      entity_type: (data.entity_type as string) || app.business_profile.entity_type,
    },
  };
}

function mapCoi(data: Record<string, unknown>, app: Application): PartialApp {
  return {
    business_profile: {
      ...app.business_profile,
      legal_name: (data.company_name as string) || app.business_profile.legal_name,
      incorporation_date:
        (data.incorporation_date as string) || app.business_profile.incorporation_date,
    },
  };
}

function mapProofOfAddress(data: Record<string, unknown>, app: Application): PartialApp {
  if (app.addresses.length > 0) return {};
  return {
    addresses: [
      {
        id: randomId("addr"),
        type: "REGISTERED",
        line1: (data.line1 as string) || "",
        line2: (data.line2 as string) || undefined,
        city: (data.city as string) || "",
        emirate: (data.emirate as string) || undefined,
        country: (data.country as string) || "AE",
        postal_code: (data.postal_code as string) || undefined,
      },
    ],
  };
}

const MAPPERS: Record<
  DocumentType,
  (data: Record<string, unknown>, app: Application) => PartialApp
> = {
  MEMORANDUM_OF_ASSOCIATION: mapMemorandum,
  PASSPORT: mapPassport,
  EMIRATES_ID: mapNationalId,
  BANK_STATEMENT: mapBankStatement,
  TRADE_LICENSE: mapTradeLicense,
  CERTIFICATE_OF_INCORPORATION: mapCoi,
  PROOF_OF_ADDRESS: mapProofOfAddress,
  OTHER: () => ({}),
};

export function mapExtractionToApplication(
  results: ExtractionResult[],
  docTypes: DocumentType[],
  app: Application,
): PartialApp {
  let merged: PartialApp = {};

  for (let i = 0; i < results.length; i++) {
    const result = results[i];
    const docType = docTypes[i];
    if (!result.success || !result.data) continue;

    const mapper = MAPPERS[docType];
    const partial = mapper(result.data, { ...app, ...merged } as Application);
    merged = deepMerge(merged, partial);
  }

  return merged;
}

function deepMerge(a: PartialApp, b: PartialApp): PartialApp {
  const result = { ...a };
  for (const [key, value] of Object.entries(b)) {
    const k = key as keyof PartialApp;
    if (
      value &&
      typeof value === "object" &&
      !Array.isArray(value) &&
      a[k] &&
      typeof a[k] === "object" &&
      !Array.isArray(a[k])
    ) {
      (result as Record<string, unknown>)[key] = { ...(a[k] as object), ...(value as object) };
    } else {
      (result as Record<string, unknown>)[key] = value;
    }
  }
  return result;
}
