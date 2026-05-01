/**
 * meta — read-only public endpoints: /api/info, /api/info/normalization-rules,
 * /api/openapi, /api/docs.
 */
import { describe, expect, it } from 'vitest'

import { config } from '../src/env.ts'

type AnyJson = Record<string, unknown>

describe('meta — /api/info, /api/openapi, /api/docs', () => {
  it('GET /api/info → 200 with status + version + timestamp', async () => {
    const res = await fetch(`${config.baseUrl}/api/info`)
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body.status).toBe('ok')
    expect(body.version).toEqual(expect.any(String))
    expect(body.timestamp).toEqual(expect.any(String))
    // Within 5 seconds of now (clock skew + RTT)
    const ts = new Date(body.timestamp as string).getTime()
    expect(Math.abs(Date.now() - ts)).toBeLessThan(5_000)
  })

  it('GET /api/info returns consistent version across calls', async () => {
    const a = (await (await fetch(`${config.baseUrl}/api/info`)).json()) as AnyJson
    const b = (await (await fetch(`${config.baseUrl}/api/info`)).json()) as AnyJson
    expect(a.version).toBe(b.version)
  })

  it('GET /api/info/normalization-rules → 200', async () => {
    const res = await fetch(`${config.baseUrl}/api/info/normalization-rules`)
    expect(res.status).toBe(200)
    const body = (await res.json()) as AnyJson
    expect(body).toBeTruthy()
  })

  it('GET /api/openapi → 200 with paths + schemas', async () => {
    const res = await fetch(`${config.baseUrl}/api/openapi`)
    expect(res.status).toBe(200)
    const body = (await res.json()) as { paths: AnyJson; components: { schemas: AnyJson } }
    expect(typeof body.paths).toBe('object')
    expect(body.paths['/api/users']).toBeDefined()
    expect(body.paths['/api/account-holders']).toBeDefined()
    expect(body.components.schemas['AccountHolderRequest']).toBeDefined()
    expect(body.components.schemas['AccountHolderResponse']).toBeDefined()
  })

  it('GET /api/docs → 200 (Scalar HTML)', async () => {
    const res = await fetch(`${config.baseUrl}/api/docs`)
    expect(res.status).toBe(200)
    const text = await res.text()
    // Scalar's HTML shell — minimal sanity that we got HTML back, not JSON.
    expect(text.toLowerCase()).toContain('<!doctype html')
  })
})
