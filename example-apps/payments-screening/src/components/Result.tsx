import type { ReactNode } from 'react'
import {
  AlertTriangle,
  Loader2,
  ScanSearch,
  Shield,
  ShieldAlert,
  ShieldCheck,
  ShieldX,
  type LucideIcon,
} from 'lucide-react'
import { cn } from '@/lib/cn'
import { formatScore, rowTone, titleCase, typeLabel, verdict, type Tone } from '@/lib/screening'
import type { ComplianceScreening, SanctionsMatch } from '@/lib/types'
import { Disclosure, JsonBlock } from './ui'
import { Badge, ToneDot } from './status'
import { toneSurface } from '@/lib/tones'

export type ResultState =
  | { kind: 'idle' }
  | { kind: 'loading' }
  | { kind: 'error'; status: number | null; message: string; detail?: unknown }
  | { kind: 'done'; rows: ComplianceScreening[]; status: number }

const VERDICT_ICON: Record<Tone, LucideIcon> = {
  ok: ShieldCheck,
  warn: ShieldAlert,
  bad: ShieldX,
  pending: Shield,
}

function SectionTitle({ children }: { children: string }) {
  return (
    <h3 className="mb-2.5 text-[0.7rem] font-semibold uppercase tracking-[0.1em] text-ink-faint">
      {children}
    </h3>
  )
}

function matchName(m: SanctionsMatch): string {
  if (m.matched_name) return m.matched_name
  const joined = [m.person_data?.given_name, m.person_data?.family_name].filter(Boolean).join(' ')
  return joined || '—'
}

function rowDetail(r: ComplianceScreening): string {
  const type = String(r.screening_type ?? '').toLowerCase()
  if (type === 'sanctions') {
    const n = typeof r.match_count === 'number' ? r.match_count : 0
    if (n > 0) return `${n} ${n === 1 ? 'match' : 'matches'}`
    const sanc = r.sanctions_screening_status
    return sanc ? titleCase(String(sanc)) : 'No sanctions match'
  }
  if (type === 'pep') {
    return r.pep_indicator ? `Flagged${r.pep_list_name ? ` · ${r.pep_list_name}` : ''}` : 'No PEP match'
  }
  if (type === 'aml') {
    return r.aml_high_risk_country
      ? `High-risk geography · ${r.aml_high_risk_country}`
      : titleCase(String(r.screening_status ?? 'reviewed'))
  }
  return titleCase(String(r.screening_status ?? 'reviewed'))
}

/* ── Panel states ──────────────────────────────────────────────────────── */
function Centered({ children }: { children: ReactNode }) {
  return <div className="flex min-h-[26rem] flex-col items-center justify-center gap-4 px-8 text-center">{children}</div>
}

function Idle() {
  return (
    <Centered>
      <ScanSearch className="size-10 text-ink-faint" strokeWidth={1.5} />
      <div className="max-w-sm">
        <p className="font-display text-lg text-ink-muted">No screening yet</p>
        <p className="mt-1.5 text-sm text-ink-faint">
          Pick a preset or fill the form, then run a screening to see the verdict, the per-check
          breakdown, and any sanctions matches.
        </p>
      </div>
    </Centered>
  )
}

function Loading() {
  return (
    <Centered>
      <div className="relative grid size-14 place-items-center">
        <span className="absolute inset-0 rounded-full border border-accent/20" />
        <Loader2 className="size-7 animate-spin text-accent" />
      </div>
      <div>
        <p className="font-display text-lg text-ink">Screening…</p>
        <p className="mt-1 text-sm text-ink-faint">Checking sanctions, PEP, and AML lists.</p>
      </div>
    </Centered>
  )
}

function ErrorView({ status, message, detail }: { status: number | null; message: string; detail?: unknown }) {
  return (
    <div className="flex flex-col gap-4 animate-rise">
      <div className={cn('rounded-xl border p-5', toneSurface.bad)}>
        <div className="flex items-center gap-3">
          <AlertTriangle className="size-6 shrink-0" />
          <h2 className="font-display text-lg font-semibold">
            Screening failed{status != null ? ` · ${status}` : ''}
          </h2>
        </div>
        <p className="mt-2 text-sm opacity-85">{message}</p>
      </div>
      {detail != null ? (
        <Disclosure summary="Error detail">
          <JsonBlock value={detail} />
        </Disclosure>
      ) : null}
    </div>
  )
}

function Done({ rows, status }: { rows: ComplianceScreening[]; status: number }) {
  const v = verdict(rows)
  const Icon = VERDICT_ICON[v.tone]
  const entityName = rows.find((r) => r.screened_entity_name)?.screened_entity_name ?? ''
  const matches = rows.flatMap((r) => r.sanctions_matches ?? [])

  return (
    <div className="flex flex-col gap-6 animate-rise">
      <div className={cn('flex items-start gap-4 rounded-xl border p-5', toneSurface[v.tone])}>
        <Icon className="size-7 shrink-0" />
        <div className="min-w-0 flex-1">
          <h2 className="font-display text-xl font-semibold tracking-tight">{v.title}</h2>
          <p className="mt-0.5 text-sm opacity-80">{v.subtitle}</p>
        </div>
        {entityName ? (
          <div className="hidden text-right sm:block">
            <div className="text-[0.65rem] uppercase tracking-[0.1em] opacity-60">Screened</div>
            <div className="font-mono text-sm">{entityName}</div>
          </div>
        ) : null}
      </div>

      <section>
        <SectionTitle>Checks</SectionTitle>
        <div className="overflow-hidden rounded-xl border border-line bg-panel/40">
          {rows.length === 0 ? (
            <p className="px-4 py-4 text-sm text-ink-faint">No screening rows returned.</p>
          ) : (
            rows.map((r, i) => (
              <div
                key={r.id ?? i}
                className="flex items-center gap-3 border-t border-line px-4 py-3 first:border-t-0"
              >
                <ToneDot tone={rowTone(r)} className="size-2.5" />
                <div className="w-24 shrink-0 font-medium text-ink">{typeLabel(r.screening_type)}</div>
                <div className="flex-1 truncate text-sm text-ink-muted">{rowDetail(r)}</div>
                <div className="w-12 shrink-0 text-right font-mono text-sm text-ink">
                  {formatScore(r.screening_score)}
                </div>
              </div>
            ))
          )}
        </div>
      </section>

      {matches.length > 0 ? (
        <section>
          <SectionTitle>{`Sanctions matches (${matches.length})`}</SectionTitle>
          <div className="overflow-x-auto rounded-xl border border-line">
            <table className="w-full border-collapse text-sm">
              <thead>
                <tr className="text-left text-[0.65rem] uppercase tracking-[0.08em] text-ink-faint">
                  <th className="px-4 py-2.5 font-medium">Name</th>
                  <th className="px-4 py-2.5 font-medium">Type</th>
                  <th className="px-4 py-2.5 font-medium">Score</th>
                  <th className="px-4 py-2.5 font-medium">List</th>
                  <th className="px-4 py-2.5 font-medium">Country</th>
                </tr>
              </thead>
              <tbody>
                {matches.map((m, i) => (
                  <tr key={i} className="border-t border-line">
                    <td className="px-4 py-2.5 font-medium text-ink">
                      {matchName(m)}
                      {m.source_data?.title ? (
                        <span className="block text-xs font-normal text-ink-faint">{m.source_data.title}</span>
                      ) : null}
                    </td>
                    <td className="px-4 py-2.5 text-ink-muted">{m.matched_entity_type ?? '—'}</td>
                    <td className="px-4 py-2.5 font-mono text-ink">{formatScore(m.match_score)}</td>
                    <td className="px-4 py-2.5 font-mono text-ink-muted">{m.source_list ?? '—'}</td>
                    <td className="px-4 py-2.5 font-mono text-ink-muted">{m.addresses?.[0]?.country ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      ) : null}

      <div>
        <Badge tone="pending">{`HTTP ${status}`}</Badge>
      </div>
      <Disclosure summary="Raw response">
        <JsonBlock value={{ data: rows }} />
      </Disclosure>
    </div>
  )
}

export function ResultPanel({ state }: { state: ResultState }) {
  switch (state.kind) {
    case 'idle':
      return <Idle />
    case 'loading':
      return <Loading />
    case 'error':
      return <ErrorView status={state.status} message={state.message} detail={state.detail} />
    case 'done':
      return <Done rows={state.rows} status={state.status} />
  }
}
