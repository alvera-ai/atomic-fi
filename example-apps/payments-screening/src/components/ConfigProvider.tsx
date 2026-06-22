import { useCallback, useState, type ReactNode } from 'react'
import { ConfigContext, loadConfig, STORAGE_KEY, type ApiConfig } from '@/lib/config'

export function ConfigProvider({ children }: { children: ReactNode }) {
  const [config, setState] = useState<ApiConfig>(loadConfig)

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
