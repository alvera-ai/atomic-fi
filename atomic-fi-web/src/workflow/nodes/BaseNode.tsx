import { Handle, Position } from 'reactflow'
import type { MouseEvent, ReactNode } from 'react'
import { useOpenNode } from './EditContext'

type Accent = 'sage' | 'terracotta' | 'violet' | 'amber'

type Props = {
  nodeId: string
  kind: string
  name: string
  accent: Accent
  hasInput?: boolean
  hasOutput?: boolean
  meta?: ReactNode
  body?: ReactNode
}

const dot: Record<Accent, string> = {
  sage: 'bg-sage',
  terracotta: 'bg-terracotta',
  violet: 'bg-violet',
  amber: 'bg-amber',
}

const ring: Record<Accent, string> = {
  sage: 'shadow-[inset_0_0_0_1px_var(--color-sage-soft)]',
  terracotta: 'shadow-[inset_0_0_0_1px_var(--color-terracotta-soft)]',
  violet: 'shadow-[inset_0_0_0_1px_var(--color-violet-soft)]',
  amber: 'shadow-[inset_0_0_0_1px_var(--color-amber-soft)]',
}

export function BaseNode({
  nodeId,
  kind,
  name,
  accent,
  hasInput = true,
  hasOutput = true,
  meta,
  body,
}: Props) {
  const openNode = useOpenNode()

  const handleEditClick = (event: MouseEvent<HTMLButtonElement>) => {
    event.stopPropagation()
    openNode?.(nodeId)
  }

  const swallow = (event: MouseEvent<HTMLButtonElement>) => event.stopPropagation()

  return (
    <div
      className={`group relative min-w-[220px] max-w-[300px] rounded-lg border border-rule bg-paper ${ring[accent]}`}
    >
      {hasInput && <Handle type="target" position={Position.Left} />}

      <div className="flex items-center gap-2 px-3.5 pt-2.5">
        <span className={`h-1.5 w-1.5 rounded-full ${dot[accent]}`} />
        <span className="eyebrow">{kind}</span>
      </div>

      <div className="px-3.5 pb-3 pt-1.5">
        <div className="truncate text-[13.5px] font-medium leading-tight text-ink">
          {name || <span className="text-ink-3">Untitled</span>}
        </div>
        {meta && <div className="mt-1.5 text-[11px] text-ink-3">{meta}</div>}
      </div>

      {body && (
        <div className="border-t border-rule px-3.5 py-2 text-[11px] text-ink-3">
          {body}
        </div>
      )}

      {openNode && (
        <button
          type="button"
          onClick={handleEditClick}
          onMouseDown={swallow}
          onDoubleClick={swallow}
          aria-label={`Edit ${name || kind}`}
          className="absolute right-1.5 top-1.5 grid h-6 w-6 place-items-center rounded-md text-ink-4 opacity-0 transition hover:bg-paper-2 hover:text-accent group-hover:opacity-100 focus:opacity-100 focus:outline-none focus:ring-1 focus:ring-accent"
        >
          <PencilIcon />
        </button>
      )}

      {hasOutput && <Handle type="source" position={Position.Right} />}
    </div>
  )
}

function PencilIcon() {
  return (
    <svg
      width="11"
      height="11"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M12 20h9" />
      <path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z" />
    </svg>
  )
}
