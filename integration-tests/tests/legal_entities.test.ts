/**
 * legal_entities — nested PUT routes for replacing PII on the three parents
 * (AccountHolder, Counterparty, BeneficialOwner). LegalEntity has no
 * standalone REST surface (removed). Create paths exercise the nested
 * `legal_entity` cast_assoc on the parent POST; this file focuses on the
 * `PUT /api/<parent>/:id/legal-entity` routes that replace PII content.
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest'

import { mintSecondaryTenant, type SecondaryTenant } from '@atomic-fi/sdk'

import { config } from '../src/env.ts'
import {
  apiKeyHeaders,
  bearerHeaders,
  createAccountHolder,
  createBeneficialOwner,
  createCounterparty,
  postAdminSession,
  safeDelete,
  UUID_RE,
  type AnyJson,
} from '../src/test-helpers.ts'

describe('legal_entities — nested PUT /api/<parent>/:id/legal-entity', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let accountHolderId: string
  let counterpartyId: string
  let beneficialOwnerId: string

  beforeAll(async () => {
    const session = await postAdminSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-legal-entities',
    })

    const ah = await createAccountHolder(bearer, primaryTenantId)
    accountHolderId = ah.id

    const cp = await createCounterparty(bearer, primaryTenantId, accountHolderId)
    counterpartyId = cp.id

    const bo = await createBeneficialOwner(bearer, primaryTenantId, accountHolderId)
    beneficialOwnerId = bo.id
  })

  afterAll(async () => {
    if (beneficialOwnerId) await safeDelete(`/api/beneficial-owners/${beneficialOwnerId}`, bearerHeaders(bearer))
    if (counterpartyId) await safeDelete(`/api/counterparties/${counterpartyId}`, bearerHeaders(bearer))
    if (accountHolderId) await safeDelete(`/api/account-holders/${accountHolderId}`, bearerHeaders(bearer))
  })

  it('PUT /api/account-holders/:id/legal-entity → 200 replaces AH PII', async () => {
    const res = await fetch(
      `${config.baseUrl}/api/account-holders/${accountHolderId}/legal-entity`,
      {
        method: 'PUT',
        headers: bearerHeaders(bearer),
        body: JSON.stringify({
          legal_entity_type: 'individual',
          first_name: 'AHReplaced',
          last_name: 'PII',
          date_of_birth: '1980-12-31',
          citizenship_country: 'GB',
          politically_exposed_person: true,
          tenant_id: primaryTenantId,
        }),
      },
    )
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.first_name).toBe('AHReplaced')
    expect(body.politically_exposed_person).toBe(true)
    expect(body.subject_type).toBe('account_holder')
  })

  it('PUT /api/counterparties/:id/legal-entity → 200 replaces CP PII', async () => {
    const res = await fetch(
      `${config.baseUrl}/api/counterparties/${counterpartyId}/legal-entity`,
      {
        method: 'PUT',
        headers: bearerHeaders(bearer),
        body: JSON.stringify({
          legal_entity_type: 'individual',
          first_name: 'CPReplaced',
          last_name: 'PII',
          date_of_birth: '1975-06-15',
          citizenship_country: 'DE',
          politically_exposed_person: false,
          tenant_id: primaryTenantId,
        }),
      },
    )
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.first_name).toBe('CPReplaced')
    expect(body.citizenship_country).toBe('DE')
    expect(body.subject_type).toBe('counterparty')
  })

  it('PUT /api/beneficial-owners/:id/legal-entity → 200 replaces BO PII', async () => {
    const res = await fetch(
      `${config.baseUrl}/api/beneficial-owners/${beneficialOwnerId}/legal-entity`,
      {
        method: 'PUT',
        headers: bearerHeaders(bearer),
        body: JSON.stringify({
          legal_entity_type: 'individual',
          first_name: 'BOReplaced',
          last_name: 'PII',
          date_of_birth: '1970-01-01',
          citizenship_country: 'FR',
          politically_exposed_person: false,
          tenant_id: primaryTenantId,
        }),
      },
    )
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.first_name).toBe('BOReplaced')
    expect(body.subject_type).toBe('account_holder_beneficial_owner')
  })

  it('PUT /api/account-holders/:id/legal-entity → 404 for unknown account holder', async () => {
    const res = await fetch(
      `${config.baseUrl}/api/account-holders/00000000-0000-0000-0000-000000000000/legal-entity`,
      {
        method: 'PUT',
        headers: bearerHeaders(bearer),
        body: JSON.stringify({
          legal_entity_type: 'individual',
          first_name: 'X',
          last_name: 'Y',
          tenant_id: primaryTenantId,
        }),
      },
    )
    expect(res.status).toBe(404)
  })

  it('PUT /api/account-holders/:id/legal-entity → 401 without auth', async () => {
    const res = await fetch(
      `${config.baseUrl}/api/account-holders/${accountHolderId}/legal-entity`,
      {
        method: 'PUT',
        headers: { accept: 'application/json', 'content-type': 'application/json' },
        body: JSON.stringify({
          legal_entity_type: 'individual',
          tenant_id: primaryTenantId,
        }),
      },
    )
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot replace primary AH legal entity → 404', async () => {
    const res = await fetch(
      `${config.baseUrl}/api/account-holders/${accountHolderId}/legal-entity`,
      {
        method: 'PUT',
        headers: apiKeyHeaders(secondary.apiKey),
        body: JSON.stringify({
          legal_entity_type: 'individual',
          first_name: 'Attacker',
          last_name: 'X',
          tenant_id: primaryTenantId,
        }),
      },
    )
    expect(res.status).toBe(404)
  })
})
