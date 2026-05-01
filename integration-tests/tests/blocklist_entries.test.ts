/**
 * blocklist_entries — full CRUD + RLS coverage for /api/blocklist-entries.
 */
import { afterAll, beforeAll, describe, expect, it } from 'vitest'

import { mintSecondaryTenant, type SecondaryTenant } from '@atomic-fi/sdk'

import { config } from '../src/env.ts'
import {
  apiKeyHeaders,
  bearerHeaders,
  postAdminSession,
  safeDelete,
  UUID_RE,
  type AnyJson,
} from '../src/test-helpers.ts'

describe('blocklist_entries — /api/blocklist-entries', () => {
  let bearer: string
  let primaryTenantId: string
  let secondary: SecondaryTenant
  let entryId: string
  const suffix = String(Date.now())
  const term = `blocked_${suffix}`

  beforeAll(async () => {
    const session = await postAdminSession()
    bearer = session.bearer
    primaryTenantId = session.tenantId
    secondary = await mintSecondaryTenant({
      baseUrl: config.baseUrl,
      platformAdminApiKey: config.platformAdminApiKey,
      prefix: 'rls-blocklist',
    })
  })

  afterAll(async () => {
    if (entryId) await safeDelete(`/api/blocklist-entries/${entryId}`, bearerHeaders(bearer))
  })

  it('POST /api/blocklist-entries → 201', async () => {
    const res = await fetch(`${config.baseUrl}/api/blocklist-entries`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        scope: 'first_name',
        entry_type: 'exact',
        term,
        reason: 'spec-created',
        active: true,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(201)
    const body = (await res.json()) as AnyJson
    expect(body.id).toMatch(UUID_RE)
    expect(body.term).toBe(term)
    expect(body.scope).toBe('first_name')
    expect(body.active).toBe(true)
    entryId = body.id as string
  })

  it('GET /api/blocklist-entries → 200 contains created', async () => {
    const res = await fetch(`${config.baseUrl}/api/blocklist-entries?page_size=100`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[] }
    expect(body.data.some((e) => e.id === entryId)).toBe(true)
  })

  it('GET /api/blocklist-entries/:id → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/blocklist-entries/${entryId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.id).toBe(entryId)
  })

  it('PUT /api/blocklist-entries/:id → 200 deactivates entry', async () => {
    const res = await fetch(`${config.baseUrl}/api/blocklist-entries/${entryId}`, {
      method: 'PUT',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        scope: 'last_name',
        entry_type: 'exact',
        term: `${term}_updated`,
        reason: 'updated',
        active: false,
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status, await res.clone().text()).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.scope).toBe('last_name')
    expect(body.active).toBe(false)
  })

  it('GET /api/blocklist-entries?page=1&page_size=5 → 200 paginated', async () => {
    const res = await fetch(`${config.baseUrl}/api/blocklist-entries?page=1&page_size=5`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: AnyJson[]; meta: AnyJson }
    expect(body.data.length).toBeLessThanOrEqual(5)
    expect(body.meta.page_size).toBe(5)
  })

  it('POST /api/blocklist-entries → 422 on missing term', async () => {
    const res = await fetch(`${config.baseUrl}/api/blocklist-entries`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        scope: 'first_name',
        entry_type: 'exact',
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status).toBe(422)
    const body = (await res.json()) as { errors: Array<{ source: { pointer: string } }> }
    expect(body.errors.some((e) => e.source.pointer === '/term')).toBe(true)
  })

  it('POST /api/blocklist-entries → 422 on invalid regex', async () => {
    const res = await fetch(`${config.baseUrl}/api/blocklist-entries`, {
      method: 'POST',
      headers: bearerHeaders(bearer),
      body: JSON.stringify({
        scope: 'company_name',
        entry_type: 'regex',
        term: '[invalid(regex',
        tenant_id: primaryTenantId,
      }),
    })
    expect(res.status).toBe(422)
  })

  it('GET /api/blocklist-entries/:id → 404 for unknown id', async () => {
    const res = await fetch(`${config.baseUrl}/api/blocklist-entries/00000000-0000-0000-0000-000000000000`, {
      headers: bearerHeaders(bearer),
    })
    expect(res.status).toBe(404)
  })

  it('GET /api/blocklist-entries → 401 without auth', async () => {
    const res = await fetch(`${config.baseUrl}/api/blocklist-entries`, { headers: { accept: 'application/json' } })
    expect(res.status).toBe(401)
  })

  it('RLS: secondary tenant cannot see primary entry → 404', async () => {
    const res = await fetch(`${config.baseUrl}/api/blocklist-entries/${entryId}`, {
      headers: apiKeyHeaders(secondary.apiKey),
    })
    expect(res.status).toBe(404)
  })

  it('DELETE /api/blocklist-entries/:id → 204 + GET 404', async () => {
    const del = await fetch(`${config.baseUrl}/api/blocklist-entries/${entryId}`, {
      method: 'DELETE',
      headers: bearerHeaders(bearer),
    })
    expect(del.status).toBe(204)

    const get = await fetch(`${config.baseUrl}/api/blocklist-entries/${entryId}`, {
      headers: bearerHeaders(bearer),
    })
    expect(get.status).toBe(404)
    entryId = ''
  })
})
