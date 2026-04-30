/**
 * Wraps the workspace `@atomic-fi/sdk` client with auth + base URL configured
 * from `src/env.ts`. Each spec calls `buildSdk(...)` once and gets a typed
 * client ready to fire.
 *
 * Two auth modes:
 *   buildBearerSdk(bearer)   — Authorization: Bearer <token> (human session)
 *   buildApiKeySdk(apiKey)   — x-api-key: <key>              (machine session)
 *
 * Both return the same typed client; only the headers differ.
 */
import { client } from '@atomic-fi/sdk'

import { config } from './env.ts'

export type Sdk = typeof client

function withHeaders(headers: Record<string, string>): Sdk {
  client.setConfig({ baseUrl: config.baseUrl, headers })
  return client
}

export function buildBearerSdk(bearer: string): Sdk {
  return withHeaders({ authorization: `Bearer ${bearer}` })
}

export function buildApiKeySdk(apiKey: string): Sdk {
  return withHeaders({ 'x-api-key': apiKey })
}
