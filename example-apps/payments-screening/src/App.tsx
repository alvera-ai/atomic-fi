import { useState } from 'react'
import { Sidebar, type View } from './components/Sidebar'
import { SettingsPanel } from './components/Settings'
import { Datalists } from './components/Datalists'
import { SCREENER_FORMS } from './components/forms/registry'
import { ResultPanel, type ResultState } from './components/Result'
import { useConfig } from './lib/config'
import { screen } from './lib/api'
import { SCREENER_META, type ScreenerId } from './lib/screeners'

function ScreenerView({ id }: { id: ScreenerId }) {
  const { config } = useConfig()
  const meta = SCREENER_META[id]
  const Form = SCREENER_FORMS[id]
  const [result, setResult] = useState<ResultState>({ kind: 'idle' })

  async function runScreen(payload: unknown) {
    setResult({ kind: 'loading' })
    const res = await screen(meta.endpoint, payload, config)
    if (res.ok) {
      setResult({ kind: 'done', rows: res.data.data ?? [], status: res.status })
    } else {
      setResult({ kind: 'error', status: res.status, message: res.error, detail: res.detail })
    }
  }

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2">
      <section className="border-line p-7 lg:border-r lg:p-9">
        <header className="mb-7">
          <div className="flex items-center gap-2 font-mono text-xs text-ink-faint">
            <span className="rounded border border-line bg-panel px-1.5 py-0.5 text-accent">POST</span>
            <span className="truncate">{meta.endpoint}</span>
          </div>
          <h1 className="mt-3 font-display text-2xl font-semibold tracking-tight text-ink">{meta.label}</h1>
          <p className="mt-1 text-sm text-ink-muted">{meta.blurb}</p>
        </header>
        {/* key resets form state when switching screeners */}
        <Form key={id} onSubmit={(p) => void runScreen(p)} busy={result.kind === 'loading'} />
      </section>

      <section className="p-7 lg:p-9">
        <ResultPanel state={result} />
      </section>
    </div>
  )
}

export default function App() {
  const [view, setView] = useState<View>('account-holder')

  return (
    <div className="flex min-h-svh">
      <Sidebar view={view} onSelect={setView} />
      <main className="grid-texture flex-1">
        {view === 'settings' ? (
          <div className="mx-auto max-w-2xl p-8 lg:p-12">
            <SettingsPanel />
          </div>
        ) : (
          <ScreenerView id={view} />
        )}
      </main>
      <Datalists />
    </div>
  )
}
