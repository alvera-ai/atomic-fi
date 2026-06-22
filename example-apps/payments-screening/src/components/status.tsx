import { cn } from '@/lib/cn'
import type { Tone } from '@/lib/screening'
import { toneDotColor, toneSurface } from '@/lib/tones'

export function ToneDot({ tone, className }: { tone: Tone; className?: string }) {
  return <span className={cn('inline-block size-2 shrink-0 rounded-full', toneDotColor[tone], className)} />
}

export function Badge({ tone, children }: { tone: Tone; children: string }) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-medium',
        toneSurface[tone],
      )}
    >
      {children}
    </span>
  )
}
