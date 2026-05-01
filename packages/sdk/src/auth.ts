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
