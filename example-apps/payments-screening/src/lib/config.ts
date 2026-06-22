import { createContext, useContext } from 'react'

export interface ApiConfig {
  /** API origin. Blank = same-origin (the Vite dev proxy forwards to the API). */
  baseUrl: string
  apiKey: string
}

export const STORAGE_KEY = 'payments-screening.config'
const DEFAULT_API_KEY = 'alvera_root_api_key_dev'

/** This app's own origin. Requests to it are proxied to the API in dev. */
function originBaseUrl(): string {
  return typeof window === 'undefined' ? '' : window.location.origin
}

export function loadConfig(): ApiConfig {
  const fallback: ApiConfig = { baseUrl: originBaseUrl(), apiKey: DEFAULT_API_KEY }
  // Persisted config is untrusted input: a corrupt blob falls back to defaults
  // rather than wedging the whole app on boot. An empty stored base URL also
  // falls back to the origin so the field is always populated.
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw) {
      const stored = JSON.parse(raw) as Partial<ApiConfig>
      return {
        baseUrl: stored.baseUrl?.trim() ? stored.baseUrl : fallback.baseUrl,
        apiKey: stored.apiKey ?? fallback.apiKey,
      }
    }
  } catch {
    /* corrupt storage — use fallback */
  }
  return fallback
}

export type TenantState = 'resolving' | 'ready' | 'error'

export interface ConfigContextValue {
  config: ApiConfig
  setConfig: (next: ApiConfig) => void
  /** Tenant resolved from the API key — required on every screening request. */
  tenantId: string | null
  tenantSlug: string | null
  tenantState: TenantState
}

export const ConfigContext = createContext<ConfigContextValue | null>(null)

export function useConfig(): ConfigContextValue {
  const ctx = useContext(ConfigContext)
  if (!ctx) throw new Error('useConfig must be used within <ConfigProvider>')
  return ctx
}
