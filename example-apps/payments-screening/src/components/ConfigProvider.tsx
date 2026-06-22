import { useCallback, useEffect, useState, type ReactNode } from 'react'
import {
  ConfigContext,
  loadConfig,
  STORAGE_KEY,
  type ApiConfig,
  type TenantState,
} from '@/lib/config'
import { fetchTenants, refreshBlocklistCache } from '@/lib/api'

export function ConfigProvider({ children }: { children: ReactNode }) {
  const [config, setState] = useState<ApiConfig>(loadConfig)
  const [tenantId, setTenantId] = useState<string | null>(null)
  const [tenantSlug, setTenantSlug] = useState<string | null>(null)
  const [tenantState, setTenantState] = useState<TenantState>('resolving')

  const setConfig = useCallback((next: ApiConfig) => {
    setState(next)
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(next))
    } catch {
      /* storage unavailable (private mode) — keep in-memory config */
    }
  }, [])

  // Resolve the tenant from the key and prime its blocklist cache (a screening
  // prerequisite). Re-runs whenever the base URL or key changes.
  useEffect(() => {
    let cancelled = false
    void (async () => {
      setTenantState('resolving')
      const res = await fetchTenants(config)
      if (cancelled) return
      if (!res.ok || res.tenants.length === 0) {
        setTenantId(null)
        setTenantSlug(null)
        setTenantState('error')
        return
      }
      const tenant = res.tenants[0]
      setTenantId(tenant.id)
      setTenantSlug(tenant.slug)
      setTenantState('ready')
      void refreshBlocklistCache(config)
    })()
    return () => {
      cancelled = true
    }
  }, [config])

  return (
    <ConfigContext value={{ config, setConfig, tenantId, tenantSlug, tenantState }}>
      {children}
    </ConfigContext>
  )
}
