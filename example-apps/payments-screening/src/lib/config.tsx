import { createContext, useCallback, useContext, useState, type ReactNode } from 'react'

export interface ApiConfig {
  /** API origin. Blank = same-origin (the Vite dev proxy forwards to the API). */
  baseUrl: string
  apiKey: string
}

const DEFAULTS: ApiConfig = { baseUrl: '', apiKey: 'alvera_root_api_key_dev' }
const STORAGE_KEY = 'payments-screening.config'

function load(): ApiConfig {
  // Persisted config is untrusted input: a corrupt blob falls back to defaults
  // rather than wedging the whole app on boot.
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (raw) return { ...DEFAULTS, ...(JSON.parse(raw) as Partial<ApiConfig>) }
  } catch {
    /* corrupt storage — use defaults */
  }
  return DEFAULTS
}

interface ConfigContextValue {
  config: ApiConfig
  setConfig: (next: ApiConfig) => void
}

const ConfigContext = createContext<ConfigContextValue | null>(null)

export function ConfigProvider({ children }: { children: ReactNode }) {
  const [config, setState] = useState<ApiConfig>(load)

  const setConfig = useCallback((next: ApiConfig) => {
    setState(next)
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(next))
    } catch {
      /* storage unavailable (private mode) — keep in-memory config */
    }
  }, [])

  return <ConfigContext value={{ config, setConfig }}>{children}</ConfigContext>
}

export function useConfig(): ConfigContextValue {
  const ctx = useContext(ConfigContext)
  if (!ctx) throw new Error('useConfig must be used within <ConfigProvider>')
  return ctx
}
