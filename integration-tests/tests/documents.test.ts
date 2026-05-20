/**
 * documents — full CRUD + RLS for /api/documents.
 *
 * Documents belong to an account_holder. We provision a legal_entity +
 * account_holder in beforeAll.
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest'

import { mintSecondaryTenant, type SecondaryTenant } from '@atomic-fi/sdk'

import { config } from '../src/env.ts'
import {
  apiKeyHeaders,
  bearerHeaders,
  createAccountHolder,
  postAdminSession,
  safeDelete,
  UUID_RE,
  warmupBlocklistCache,
  type AnyJson,
} from '../src/test-helpers.ts'

describe('documents — /api/documents', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let accountHolderId: string
  let documentId: string

  beforeAll(async () => {
    const session = await postAdminSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-documents',
    })

    await warmupBlocklistCache(bearer)
    const ah = await createAccountHolder(bearer, primaryTenantId)
    accountHolderId = ah.id
  })

  afterAll(async () => {
    if (documentId) await safeDelete(`/api/documents/${documentId}`, bearerHeaders(bearer))
    if (accountHolderId) await safeDelete(`/api/account-holders/${accountHolderId}`, bearerHeaders(bearer))
  })

  it('POST /api/documents → 201', async () => {
    const res = await fetch(`${config.baseUrl}/api/documents`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        document_type: 'identity_document',
        name: 'kyc_passport',
        primary: true,
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.document_type).toBe('identity_document')
    expect(body.name).toBe('kyc_passport')
    documentId = body.id as string
  })

  it('GET /api/documents → 200 contains created', async () => {
    const res = await fetch(`${config.baseUrl}/api/documents?page_size=100&order_by=inserted_at&order_directions=desc`, { headers: bearerHeaders(bearer) })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[] }
    expect(body.data.some((d) => d.id === documentId)).toBe(true)
  })

  it('GET /api/documents/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/documents/${documentId}`, { headers: bearerHeaders(bearer) })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(documentId)
  })

  it('PUT /api/documents/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/documents/${documentId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        document_type: 'identity_document',
        name: 'kyc_passport',
        status: 'submitted',
        primary: true,
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.status).toBe('submitted')
  })

  it('GET /api/documents?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/documents?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/documents → 422 on missing document_type', async () => {
    const res = await fetch(`${config.baseUrl}/api/documents`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        name: 'no-type',
        primary: false,
        account_holder_id: accountHolderId,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/documents/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/documents/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/documents → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/documents`, { headers: { accept: 'application/json' } })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary document → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/documents/${documentId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/documents/:id → 204 + GET 404', async () => {
    const del = await fetch(`${config.baseUrl}/api/documents/${documentId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/documents/${documentId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(get.status).toBe(404)
    documentId = ''
  })
})
