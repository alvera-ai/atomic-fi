import { Handle, Position } from 'reactflow'
import type { ReactNode } from 'react'

type Props = {
  title: string
  subtitle: string
  accent: string
  hasInput?: boolean
  hasOutput?: boolean
  children?: ReactNode
}

export function BaseNode({ title, subtitle, accent, hasInput = true, hasOutput = true, children }: Props) {
  return (
    <div className="min-w-[180px] rounded-lg border border-slate-300 bg-white shadow-sm">
      {hasInput && <Handle type="target" position={Position.Left} className="!h-3 !w-3 !bg-slate-400" />}
      <div className={`rounded-t-lg px-3 py-2 text-xs font-semibold uppercase tracking-wide ${accent}`}>
        {subtitle}
      </div>
      <div className="px-3 py-2 text-sm font-medium text-slate-800">{title}</div>
      {children && <div className="border-t border-slate-200 px-3 py-2 text-xs text-slate-500">{children}</div>}
      {hasOutput && <Handle type="source" position={Position.Right} className="!h-3 !w-3 !bg-slate-400" />}
    </div>
  )
}
