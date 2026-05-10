// Centralised mock API. Function names mirror operationIds in atomicfi-openapi.yaml.
// Swap each function body for the @atomic-fi/sdk equivalent at rewire time.
import {
  accountHolders as fxAccountHolders,
  apiInfo as fxApiInfo,
  apiKeys as fxApiKeys,
  beneficialOwners,
  complianceScreenings as fxComplianceScreenings,
  counterparties as fxCounterparties,
  documents as fxDocuments,
  kycRequirements as fxKycRequirements,
  ledgerAccountBalances,
  ledgerEntries,
  recommendations as fxRecommendations,
  sanctionsMatches as fxSanctionsMatches,
  tenants as fxTenants,
  transactions as fixtureTransactions,
  TENANT_ID,
} from "@/data/fixtures";
import type {
  AccountHolderResponse,
  ApiInfoResponse,
  ApiKeyResponse,
  BeneficialOwnerResponse,
  ComplianceScreeningResponse,
  CounterpartyResponse,
  DocumentResponse,
  KycRequirementResponse,
  LedgerAccountBalanceResponse,
  LedgerEntryResponse,
  Recommendation,
  SanctionsMatchResponse,
  TenantResponse,
  TransactionResponse,
} from "@/api/types";

const delay = <T,>(value: T, ms = 250) => new Promise<T>((r) => setTimeout(() => r(value), ms));
const newId = () => crypto.randomUUID();
const now = () => new Date().toISOString();

// ─── Mutable in-memory stores
let txStore: TransactionResponse[] = [...fixtureTransactions];
let holderStore: AccountHolderResponse[] = [...fxAccountHolders];
let cpStore: CounterpartyResponse[] = [...fxCounterparties];
let kycStore: KycRequirementResponse[] = [...fxKycRequirements];
let docStore: DocumentResponse[] = [...fxDocuments];
let screeningStore: ComplianceScreeningResponse[] = [...fxComplianceScreenings];
let matchStore: SanctionsMatchResponse[] = [...fxSanctionsMatches];
let apiKeyStore: ApiKeyResponse[] = [...fxApiKeys];
let tenantStore: TenantResponse[] = [...fxTenants];
let recStore: Recommendation[] = [...fxRecommendations];

// ─── Transactions
export const listTransactions = (): Promise<TransactionResponse[]> => delay([...txStore]);
export const getTransaction = (id: string) => delay(txStore.find((t) => t.id === id));
export const updateTransaction = (id: string, patch: Partial<TransactionResponse>): Promise<TransactionResponse> => {
  txStore = txStore.map((t) => (t.id === id ? { ...t, ...patch, updated_at: now() } : t));
  return delay(txStore.find((t) => t.id === id)!, 350);
};

// ─── Account holders
export const listAccountHolders = (): Promise<AccountHolderResponse[]> => delay([...holderStore]);
export const getAccountHolder = (id: string) => delay(holderStore.find((a) => a.id === id));
export const updateAccountHolder = (id: string, patch: Partial<AccountHolderResponse>): Promise<AccountHolderResponse> => {
  holderStore = holderStore.map((a) => (a.id === id ? { ...a, ...patch, updated_at: now() } : a));
  return delay(holderStore.find((a) => a.id === id)!, 300);
};

// ─── Counterparties
export const listCounterparties = (): Promise<CounterpartyResponse[]> => delay([...cpStore]);
export const getCounterparty = (id: string) => delay(cpStore.find((c) => c.id === id));
export const updateCounterparty = (id: string, patch: Partial<CounterpartyResponse>): Promise<CounterpartyResponse> => {
  cpStore = cpStore.map((c) => (c.id === id ? { ...c, ...patch, updated_at: now() } : c));
  return delay(cpStore.find((c) => c.id === id)!, 300);
};

// ─── Beneficial owners
export const listBeneficialOwners = (counterpartyId?: string): Promise<BeneficialOwnerResponse[]> =>
  delay(counterpartyId ? beneficialOwners.filter((b) => b.counterparty_id === counterpartyId) : beneficialOwners);

// ─── KYC
export const listKycRequirements = (accountHolderId?: string): Promise<KycRequirementResponse[]> =>
  delay(accountHolderId ? kycStore.filter((k) => k.account_holder_id === accountHolderId) : [...kycStore]);
export const updateKycRequirement = (id: string, patch: Partial<KycRequirementResponse>): Promise<KycRequirementResponse> => {
  kycStore = kycStore.map((k) => (k.id === id ? { ...k, ...patch, updated_at: now() } : k));
  return delay(kycStore.find((k) => k.id === id)!, 300);
};
export const createKycRequirement = (input: Omit<KycRequirementResponse, "id" | "inserted_at" | "updated_at">): Promise<KycRequirementResponse> => {
  const created: KycRequirementResponse = { ...input, id: newId(), inserted_at: now(), updated_at: now() };
  kycStore = [created, ...kycStore];
  return delay(created, 250);
};

// ─── Documents
export const listDocuments = (accountHolderId?: string): Promise<DocumentResponse[]> =>
  delay(accountHolderId ? docStore.filter((d) => d.account_holder_id === accountHolderId) : [...docStore]);
export const createDocument = (input: Omit<DocumentResponse, "id" | "uploaded_at">): Promise<DocumentResponse> => {
  const created: DocumentResponse = { ...input, id: newId(), uploaded_at: now() };
  docStore = [created, ...docStore];
  return delay(created, 250);
};

// ─── Compliance screenings + matches
export const listComplianceScreenings = (): Promise<ComplianceScreeningResponse[]> => delay([...screeningStore]);
export const getComplianceScreening = (id: string) => delay(screeningStore.find((s) => s.id === id));
export const updateComplianceScreening = (id: string, patch: Partial<ComplianceScreeningResponse>): Promise<ComplianceScreeningResponse> => {
  screeningStore = screeningStore.map((s) => (s.id === id ? { ...s, ...patch } : s));
  return delay(screeningStore.find((s) => s.id === id)!, 250);
};
export const screenAccountHolder = async (id: string): Promise<ComplianceScreeningResponse> => {
  const created: ComplianceScreeningResponse = {
    id: newId(), subject_type: "account_holder", subject_id: id,
    status: "clear", provider: "ComplyAdvantage", screened_at: now(), reviewer: null,
  };
  screeningStore = [created, ...screeningStore];
  return delay(created, 600);
};
export const screenCounterparty = async (id: string): Promise<ComplianceScreeningResponse> => {
  const created: ComplianceScreeningResponse = {
    id: newId(), subject_type: "counterparty", subject_id: id,
    status: "clear", provider: "ComplyAdvantage", screened_at: now(), reviewer: null,
  };
  screeningStore = [created, ...screeningStore];
  return delay(created, 600);
};
export const screenBeneficialOwner = async (id: string): Promise<ComplianceScreeningResponse> => {
  const created: ComplianceScreeningResponse = {
    id: newId(), subject_type: "beneficial_owner", subject_id: id,
    status: "clear", provider: "ComplyAdvantage", screened_at: now(), reviewer: null,
  };
  screeningStore = [created, ...screeningStore];
  return delay(created, 600);
};

export const listSanctionsMatches = (screeningId?: string): Promise<SanctionsMatchResponse[]> =>
  delay(screeningId ? matchStore.filter((m) => m.compliance_screening_id === screeningId) : [...matchStore]);
export const updateSanctionsMatch = (id: string, patch: Partial<SanctionsMatchResponse>): Promise<SanctionsMatchResponse> => {
  matchStore = matchStore.map((m) => (m.id === id ? { ...m, ...patch } : m));
  return delay(matchStore.find((m) => m.id === id)!, 250);
};

// ─── Ledger
export const getLedgerEntry = (id: string) => delay(ledgerEntries.find((l) => l.id === id));
export const listLedgerAccountBalances = (): Promise<LedgerAccountBalanceResponse[]> => delay(ledgerAccountBalances);

// ─── API keys (POST/DELETE per spec)
export const listApiKeys = (): Promise<ApiKeyResponse[]> => delay([...apiKeyStore]);
export const createApiKey = (input: { name: string; tenant_id: string; role_id?: string }): Promise<ApiKeyResponse> => {
  const created: ApiKeyResponse = {
    id: newId(),
    name: input.name,
    customer_id: null,
    role_id: input.role_id ?? newId(),
    tenant_id: input.tenant_id,
    inserted_at: now(),
    last_used_at: null,
    raw_key: `afi_live_${crypto.randomUUID().replace(/-/g, "")}`,
  };
  apiKeyStore = [created, ...apiKeyStore];
  return delay(created, 350);
};
export const deleteApiKey = (id: string): Promise<{ ok: true }> => {
  apiKeyStore = apiKeyStore.filter((k) => k.id !== id);
  return delay({ ok: true }, 250);
};

// ─── Tenants
export const listTenants = (): Promise<TenantResponse[]> => delay([...tenantStore]);
export const updateTenant = (id: string, patch: Partial<TenantResponse>): Promise<TenantResponse> => {
  tenantStore = tenantStore.map((t) => (t.id === id ? { ...t, ...patch } : t));
  return delay(tenantStore.find((t) => t.id === id)!, 250);
};
export const refreshBlocklistCache = (id: string): Promise<TenantResponse> => {
  tenantStore = tenantStore.map((t) => (t.id === id ? { ...t, blocklist_refreshed_at: now() } : t));
  return delay(tenantStore.find((t) => t.id === id)!, 800);
};

// ─── API info
export const getApiInfo = (): Promise<ApiInfoResponse> =>
  delay({ ...fxApiInfo, uptime_seconds: fxApiInfo.uptime_seconds + Math.floor(Math.random() * 1000) }, 200);

// ─── Recommendations (mock — really sourced from alvera-ai/platform)
export const listRecommendations = (): Promise<Recommendation[]> => delay([...recStore]);
export const dismissRecommendation = (id: string): Promise<Recommendation> => {
  recStore = recStore.map((r) => (r.id === id ? { ...r, status: "dismissed" as const } : r));
  return delay(recStore.find((r) => r.id === id)!, 200);
};
export const approveRecommendation = async (id: string): Promise<Recommendation> => {
  const rec = recStore.find((r) => r.id === id);
  if (!rec) throw new Error("Recommendation not found");
  // Each kind dispatches the matching AtomicFi write.
  switch (rec.kind) {
    case "add_blocklist_entry": {
      // POST /api/blocklist-entries — mock no-op for v1
      break;
    }
    case "raise_risk_classification": {
      const next = (rec.payload.to ?? "high") as AccountHolderResponse["risk_level"];
      await updateAccountHolder(rec.subject_id, { risk_level: next });
      break;
    }
    case "request_kyc_document": {
      await createKycRequirement({
        account_holder_id: rec.subject_id,
        requirement_type: String(rec.payload.requirement_type ?? "additional_document"),
        status: "pending",
        document_id: null,
        notes: "Auto-created from recommendation",
      });
      break;
    }
    case "suspend_counterparty": {
      await updateCounterparty(rec.subject_id, { status: "suspended" });
      break;
    }
  }
  recStore = recStore.map((r) => (r.id === id ? { ...r, status: "approved" as const } : r));
  return recStore.find((r) => r.id === id)!;
};

export { TENANT_ID };
