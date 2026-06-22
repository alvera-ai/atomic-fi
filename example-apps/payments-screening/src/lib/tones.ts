import type { Tone } from './screening'

// Tailwind class maps for the verdict tones. Pure data, shared by the status
// components and the result panel.

export const toneDotColor: Record<Tone, string> = {
  ok: 'bg-ok',
  warn: 'bg-warn',
  bad: 'bg-bad',
  pending: 'bg-pending',
}

export const toneSurface: Record<Tone, string> = {
  ok: 'border-ok/30 bg-ok/10 text-ok',
  warn: 'border-warn/30 bg-warn/10 text-warn',
  bad: 'border-bad/35 bg-bad/[0.12] text-bad',
  pending: 'border-pending/25 bg-pending/10 text-pending',
}
