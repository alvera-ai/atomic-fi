import { useState } from 'react'
import { Check, Eye, EyeOff, Loader2, Plug } from 'lucide-react'
import { toast } from 'sonner'
import { Button, Field, TextInput } from './ui'
import { useConfig } from '@/lib/config'
import { fetchTenants } from '@/lib/api'
import { cn } from '@/lib/cn'

type TestState = { kind: 'idle' } | { kind: 'testing' } | { kind: 'ok'; msg: string } | { kind: 'fail'; msg: string }

export function SettingsPanel() {
  const { config, setConfig, tenantSlug, tenantState } = useConfig()
  const [baseUrl, setBaseUrl] = useState(config.baseUrl)
  const [apiKey, setApiKey] = useState(config.apiKey)
  const [reveal, setReveal] = useState(false)
  const [test, setTest] = useState<TestState>({ kind: 'idle' })

  const dirty = baseUrl !== config.baseUrl || apiKey !== config.apiKey

  function save() {
    setConfig({ baseUrl: baseUrl.trim(), apiKey: apiKey.trim() })
    toast.success('Settings saved')
  }

  async function testConnection() {
    setTest({ kind: 'testing' })
    const res = await fetchTenants({ baseUrl: baseUrl.trim(), apiKey: apiKey.trim() })
    if (res.ok) {
      const count = res.tenants.length
      const slug = res.tenants[0]?.slug
      setTest({ kind: 'ok', msg: `Connected — ${count} tenant${count === 1 ? '' : 's'}${slug ? ` (${slug})` : ''}.` })
    } else if (res.status === 401 || res.status === 403) {
      setTest({ kind: 'fail', msg: 'Reachable, but the API key was rejected.' })
    } else {
      setTest({ kind: 'fail', msg: res.error })
    }
  }

  return (
    <div className="flex flex-col gap-6">
      <header>
        <h1 className="font-display text-2xl font-semibold tracking-tight text-ink">Settings</h1>
        <p className="mt-1 text-sm text-ink-muted">
          Where to send screening requests, and the key to authorize them. Stored in this browser.
        </p>
      </header>

      <div className="flex flex-col gap-5 rounded-xl border border-line bg-panel/40 p-6">
        <Field
          label="Base URL"
          hint="Defaults to this app's origin (proxied to the API). Change it to call a different deployment (that origin must allow CORS)."
        >
          <TextInput
            value={baseUrl}
            onChange={(e) => setBaseUrl(e.target.value)}
            placeholder="https://api.example.com"
            className="font-mono text-xs"
            spellCheck={false}
          />
        </Field>

        <Field label="API key" hint="Sent as the X-API-Key header. The tenant is resolved from this key.">
          <div className="relative">
            <TextInput
              type={reveal ? 'text' : 'password'}
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              placeholder="alvera_root_api_key_dev"
              className="pr-10 font-mono text-xs"
              spellCheck={false}
            />
            <button
              type="button"
              onClick={() => setReveal((v) => !v)}
              className="absolute inset-y-0 right-2 grid place-items-center text-ink-faint hover:text-ink-muted"
              aria-label={reveal ? 'Hide API key' : 'Show API key'}
            >
              {reveal ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
            </button>
          </div>
        </Field>

        <div className="flex flex-wrap items-center gap-3 pt-1">
          <Button onClick={save} disabled={!dirty}>
            {dirty ? 'Save changes' : 'Saved'}
          </Button>
          <Button variant="subtle" onClick={() => void testConnection()} disabled={test.kind === 'testing'}>
            {test.kind === 'testing' ? <Loader2 className="size-4 animate-spin" /> : <Plug className="size-4" />}
            Test connection
          </Button>
          {test.kind === 'ok' || test.kind === 'fail' ? (
            <span className={cn('flex items-center gap-1.5 text-sm', test.kind === 'ok' ? 'text-ok' : 'text-bad')}>
              {test.kind === 'ok' ? <Check className="size-4" /> : null}
              {test.msg}
            </span>
          ) : null}
        </div>

        <div className="flex items-center justify-between border-t border-line pt-4 text-sm">
          <span className="text-ink-faint">Resolved tenant</span>
          <span className="font-mono text-ink-muted">
            {tenantState === 'resolving' ? 'resolving…' : tenantState === 'error' ? 'unresolved' : (tenantSlug ?? '—')}
          </span>
        </div>
      </div>

      <p className="text-xs text-ink-faint">
        Local dev default key: <span className="font-mono text-ink-muted">alvera_root_api_key_dev</span>.
      </p>
    </div>
  )
}
