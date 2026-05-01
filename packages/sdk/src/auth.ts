/**
 * Auth-mode constructors for the @atomic-fi/sdk client.
 *
 * The generated client is a singleton. These helpers configure it for one of
 * the two transport modes the platform supports:
 *
 *   buildBearerSdk(baseUrl, bearer)   — Authorization: Bearer <token>
 *   buildApiKeySdk(baseUrl, apiKey)   — x-api-key: <key>
 *
 * Both return the same typed client; only the headers + baseUrl differ.
 */
import { client } from '../generated/client.gen.ts'

export type Sdk = typeof client

function withConfig(baseUrl: string, headers: Record<string, string>): Sdk {
  client.setConfig({ baseUrl, headers })
  return client
}

export function buildBearerSdk(baseUrl: string, bearer: string): Sdk {
  return withConfig(baseUrl, { authorization: `Bearer ${bearer}` })
}

export function buildApiKeySdk(baseUrl: string, apiKey: string): Sdk {
  return withConfig(baseUrl, { 'x-api-key': apiKey })
}

/**
 * Provisions a fresh secondary tenant with its own role + api key, using a
 * platform-admin api key. Returns credentials for acting AS that tenant —
 * primarily for RLS isolation tests where you need a second principal whose
 * requests should never see the primary tenant's data.
 *
 * Three POSTs under the hood:
 *   1. POST /api/tenants    (create tenant)
 *   2. POST /api/roles      (create role inside the new tenant)
 *   3. POST /api/api-keys   (create api key bound to that role)
 *
 * The returned `apiKey` is the raw key — pass it to buildApiKeySdk to make
 * scoped requests.
 */
export type SecondaryTenant = {
  tenantId: string
  tenantSlug: string
  roleId: string
  apiKeyId: string
  apiKey: string
}

export type MintSecondaryTenantArgs = {
  baseUrl: string
  platformAdminApiKey: string
  /** Suffix to namespace the tenant; defaults to a millisecond timestamp. */
  suffix?: string
  /** Prefix for the generated tenant name + slug; defaults to 'secondary'. */
  prefix?: string
}

export async function mintSecondaryTenant(
  args: MintSecondaryTenantArgs,
): Promise<SecondaryTenant> {
  const { baseUrl, platformAdminApiKey } = args
  const suffix = args.suffix ?? String(Date.now())
  const prefix = args.prefix ?? 'secondary'
  const name = `${prefix}-${suffix}`

  const headers: Record<string, string> = {
    'x-api-key': platformAdminApiKey,
    'content-type': 'application/json',
    accept: 'application/json',
  }

  const tenantRes = await fetch(`${baseUrl}/api/tenants`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      name,
      slug: name,
      tenant_type: 'standard',
      status: 'active',
    }),
  })
  if (!tenantRes.ok) {
    throw new Error(`mintSecondaryTenant: POST /api/tenants → ${tenantRes.status}: ${await tenantRes.text()}`)
  }
  const tenant = (await tenantRes.json()) as { id: string; slug: string }

  const roleRes = await fetch(`${baseUrl}/api/roles`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      name: `${prefix}_role_${suffix}`,
      description: `Role for ${name}`,
      tenant_id: tenant.id,
    }),
  })
  if (!roleRes.ok) {
    throw new Error(`mintSecondaryTenant: POST /api/roles → ${roleRes.status}: ${await roleRes.text()}`)
  }
  const role = (await roleRes.json()) as { id: string }

  const apiKeyRes = await fetch(`${baseUrl}/api/api-keys`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      name: `${prefix}-key-${suffix}`,
      tenant_id: tenant.id,
      role_id: role.id,
    }),
  })
  if (!apiKeyRes.ok) {
    throw new Error(`mintSecondaryTenant: POST /api/api-keys → ${apiKeyRes.status}: ${await apiKeyRes.text()}`)
  }
  const apiKey = (await apiKeyRes.json()) as { id: string; raw_key: string }

  return {
    tenantId: tenant.id,
    tenantSlug: tenant.slug,
    roleId: role.id,
    apiKeyId: apiKey.id,
    apiKey: apiKey.raw_key,
  }
}
