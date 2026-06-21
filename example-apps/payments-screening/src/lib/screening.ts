import type { ComplianceScreening } from './types'

export type Tone = 'ok' | 'warn' | 'bad' | 'pending'

const lower = (v: unknown) => (v == null ? '' : String(v).toLowerCase())

/** Classify a single screening row into a verdict tone. */
export function rowTone(r: ComplianceScreening): Tone {
  const status = lower(r.screening_status)
  const sanctions = lower(r.sanctions_screening_status)
  const matches = typeof r.match_count === 'number' ? r.match_count : 0

  if (
    sanctions === 'match' ||
    sanctions === 'failed' ||
    matches > 0 ||
    ['flagged', 'hit', 'failed', 'rejected', 'blocked'].includes(status)
  ) {
    return 'bad'
  }
  if (
    r.manual_review_required === true ||
    r.pep_indicator === true ||
    r.aml_control_flag === true ||
    sanctions === 'pending' ||
    ['pending', 'in_progress', 'review', 'escalated'].includes(status)
  ) {
    return 'warn'
  }
  if (sanctions === 'cleared' || ['cleared', 'clear', 'passed', 'completed', 'approved'].includes(status)) {
    return 'ok'
  }
  return 'pending'
}

export interface Verdict {
  tone: Tone
  title: string
  subtitle: string
}

/** Roll a set of rows up into the single headline verdict (worst signal wins). */
export function verdict(rows: ComplianceScreening[]): Verdict {
  const tones = rows.map(rowTone)
  const has = (t: Tone) => tones.includes(t)

  if (has('bad')) {
    const hits = rows.reduce((n, r) => n + (typeof r.match_count === 'number' ? r.match_count : 0), 0)
    return {
      tone: 'bad',
      title: 'Match — do not proceed',
      subtitle: hits > 0 ? `${hits} sanctions ${hits === 1 ? 'match' : 'matches'} found` : 'A screening check failed',
    }
  }
  if (has('warn')) {
    const reasons: string[] = []
    if (rows.some((r) => r.pep_indicator)) reasons.push('PEP')
    if (rows.some((r) => r.manual_review_required)) reasons.push('manual review')
    if (rows.some((r) => r.aml_control_flag)) reasons.push('AML control')
    return {
      tone: 'warn',
      title: 'Review required',
      subtitle: reasons.length ? `Flagged for ${reasons.join(', ')}` : 'Screening did not fully clear',
    }
  }
  if (has('ok')) {
    return { tone: 'ok', title: 'Cleared', subtitle: 'No sanctions, PEP, or AML hits' }
  }
  return { tone: 'pending', title: 'No screening performed', subtitle: 'Nothing to screen for this request' }
}

const TYPE_LABELS: Record<string, string> = {
  sanctions: 'Sanctions',
  pep: 'PEP',
  aml: 'AML',
  adverse_media: 'Adverse media',
}

export const typeLabel = (t: unknown): string => {
  const key = lower(t)
  return TYPE_LABELS[key] ?? titleCase(key || 'Screening')
}

export function titleCase(s: string): string {
  return s.replace(/[_-]+/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())
}

/** Format a 0..1 (or 0..100) score as a percentage, or em-dash when absent. */
export function formatScore(score: number | string | null | undefined): string {
  if (score == null || score === '') return '—'
  const n = typeof score === 'string' ? Number(score) : score
  if (Number.isNaN(n)) return '—'
  const pct = n <= 1 ? n * 100 : n
  return `${pct.toFixed(pct < 10 ? 1 : 0)}%`
}
