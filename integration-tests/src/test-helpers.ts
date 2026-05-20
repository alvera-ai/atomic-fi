/**
 * Cross-spec helpers. Each spec is still self-contained — it just imports
 * these utilities so we don't repeat 30 lines of bootstrap per file.
 */
import { config } from './env.ts'

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
export const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/

export type AnyJson = Record<string, unknown>

const jsonHeaders = (extra: Record<string, string> = {}) => ({
  'content-type': 'application/json',
  accept: 'application/json',
  ...extra,
})

export const bearerHeaders = (bearer: string) => jsonHeaders({ authorization: `Bearer ${bearer}` })
export const apiKeyHeaders = (apiKey: string) => jsonHeaders({ 'x-api-key': apiKey })
export const platformAdminHeaders = () => jsonHeaders({ 'x-api-key': config.platformAdminApiKey })

/** POST /api/sessions for the seeded admin and return { bearer, tenantId }. */
export async function postAdminSession(): Promise<{ bearer: string; tenantId: string }> {
  const res = await fetch(`${config.baseUrl}/api/sessions`, {
    method: 'POST',
    headers: jsonHeaders(),
    body: JSON.stringify({
      email: config.adminEmail,
      password: config.adminPassword,
      tenant_slug: config.tenantSlug,
      expires_in: 3600,
    }),
  })
  if (!res.status.toString().startsWith('2')) {
    throw new Error(`session POST → ${res.status}: ${await res.text()}`)
  }
  const body = (await res.json()) as { bearer: string; tenant: { id: string } }
  return { bearer: body.bearer, tenantId: body.tenant.id }
}

/** Best-effort DELETE; swallows network errors so afterAll never blows up. */
export async function safeDelete(path: string, headers: Record<string, string>): Promise<void> {
  await fetch(`${config.baseUrl}${path}`, { method: 'DELETE', headers }).catch(() => {})
}

/**
 * Initialize the per-tenant BlocklistCache. AH/CP/BO POST runs
 * `OnboardingContext.onboard` synchronously, which fail-closes (500) when
 * the cache isn't populated yet. Call once in beforeAll on the primary
 * tenant before any entity creation that goes through the onboard pipeline.
 */
export async function warmupBlocklistCache(bearer: string): Promise<void> {
  const res = await fetch(`${config.baseUrl}/api/tenants/refresh-blocklist-cache`, {
    method: 'POST',
    headers: bearerHeaders(bearer),
  })
  if (!res.ok) {
    throw new Error(`refresh-blocklist-cache → ${res.status}: ${await res.text()}`)
  }
}

/** Convenience: pass the path-tail and bearer to GET a JSON resource. */
export async function getJson<T = AnyJson>(
  path: string,
  headers: Record<string, string>,
): Promise<{ status: number; body: T }> {
  const res = await fetch(`${config.baseUrl}${path}`, { headers })
  return { status: res.status, body: (await res.json()) as T }
}

/** Counter for unique fake names within a single process. */
let _uniqCounter = 0
const uniq = (): string => `${Date.now()}-${++_uniqCounter}-${Math.floor(Math.random() * 1e6)}`

/** Default nested legal_entity payload for individual identity. */
export function defaultIndividualLegalEntity(tenantId: string, label = 'Test'): AnyJson {
  const u = uniq()
  return {
    legal_entity_type: 'individual',
    first_name: `${label}First-${u}`,
    last_name: `${label}Last-${u}`,
    date_of_birth: '1990-01-01',
    citizenship_country: 'US',
    politically_exposed_person: false,
    tenant_id: tenantId,
  }
}

async function postJsonRaw(path: string, headers: Record<string, string>, body: unknown): Promise<AnyJson> {
  const res = await fetch(`${config.baseUrl}${path}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  })
  if (!res.ok) {
    throw new Error(`${path} → ${res.status}: ${await res.text()}`)
  }
  return (await res.json()) as AnyJson
}

/**
 * Create an AccountHolder with a nested individual legal_entity.
 * Returns { id, legalEntityId }.
 *
 * `chain_screening: false` is set by default so the test does not depend on Watchman.
 * Pass `overrides` to override any field at the top level; `overrides.legal_entity`
 * (if present) replaces the default nested LE payload entirely.
 */
export async function createAccountHolder(
  bearer: string,
  tenantId: string,
  overrides: Partial<AnyJson> = {},
): Promise<{ id: string; legalEntityId: string }> {
  const { legal_entity: leOverride, ...topOverrides } = overrides as AnyJson & {
    legal_entity?: AnyJson
  }
  const body: AnyJson = {
    account_holder_type: 'individual',
    status: 'pending',
    kyc_status: 'not_started',
    risk_level: 'low',
    enabled_currencies: ['USD'],
    chain_screening: false,
    tenant_id: tenantId,
    legal_entity: (leOverride as AnyJson) ?? defaultIndividualLegalEntity(tenantId, 'AH'),
    ...topOverrides,
  }
  const ah = await postJsonRaw('/api/account-holders', bearerHeaders(bearer), body)
  const le = ah.legal_entity as AnyJson | undefined
  return { id: ah.id as string, legalEntityId: (le?.id as string) ?? '' }
}

/**
 * Create a Counterparty with a nested individual legal_entity under an existing AccountHolder.
 * Returns { id, legalEntityId }.
 */
export async function createCounterparty(
  bearer: string,
  tenantId: string,
  accountHolderId: string,
  overrides: Partial<AnyJson> = {},
): Promise<{ id: string; legalEntityId: string }> {
  const { legal_entity: leOverride, ...topOverrides } = overrides as AnyJson & {
    legal_entity?: AnyJson
  }
  const body: AnyJson = {
    status: 'active',
    account_holder_id: accountHolderId,
    tenant_id: tenantId,
    chain_screening: false,
    legal_entity: (leOverride as AnyJson) ?? defaultIndividualLegalEntity(tenantId, 'CP'),
    ...topOverrides,
  }
  const cp = await postJsonRaw('/api/counterparties', bearerHeaders(bearer), body)
  const le = cp.legal_entity as AnyJson | undefined
  return { id: cp.id as string, legalEntityId: (le?.id as string) ?? '' }
}

/**
 * Create a BeneficialOwner with a nested individual legal_entity under an existing AccountHolder.
 * Returns { id, legalEntityId }.
 */
export async function createBeneficialOwner(
  bearer: string,
  tenantId: string,
  accountHolderId: string,
  overrides: Partial<AnyJson> = {},
): Promise<{ id: string; legalEntityId: string }> {
  const { legal_entity: leOverride, ...topOverrides } = overrides as AnyJson & {
    legal_entity?: AnyJson
  }
  const body: AnyJson = {
    control_type: 'shareholder',
    ownership_pct: 25.0,
    verification_status: 'pending',
    account_holder_id: accountHolderId,
    tenant_id: tenantId,
    legal_entity: (leOverride as AnyJson) ?? defaultIndividualLegalEntity(tenantId, 'BO'),
    ...topOverrides,
  }
  const bo = await postJsonRaw('/api/beneficial-owners', bearerHeaders(bearer), body)
  const le = bo.legal_entity as AnyJson | undefined
  return { id: bo.id as string, legalEntityId: (le?.id as string) ?? '' }
}
