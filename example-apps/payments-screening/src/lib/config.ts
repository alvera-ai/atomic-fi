import { createContext, useContext } from 'react'

export interface ApiConfig {
  /** API origin. Blank = same-origin (the Vite dev proxy forwards to the API). */
  baseUrl: string
  apiKey: string
}

export const DEFAULT_CONFIG: ApiConfig = { baseUrl: '', apiKey: 'alvera_root_api_key_dev' }
export const STORAGE_KEY = 'payments-screening.config'

export function loadConfig(): ApiConfig {
  // Persisted config is untrusted input: a corrupt blob falls back to defaults
  // rather than wedging the whole app on boot.
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw) return { ...DEFAULT_CONFIG, ...(JSON.parse(raw) as Partial<ApiConfig>) }
  } catch {
    /* corrupt storage — use defaults */
  }
  return DEFAULT_CONFIG
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
