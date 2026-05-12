import { NODE_KINDS } from './types'
import type { NodeKind } from './types'

export function NodePalette() {
  const onDragStart = (event: React.DragEvent, kind: NodeKind) => {
    event.dataTransfer.setData('application/x-jdm-node', kind)
    event.dataTransfer.effectAllowed = 'move'
  }

  return (
    <aside className="flex h-full w-64 shrink-0 flex-col gap-2 border-r border-slate-200 bg-slate-50 p-4">
      <h2 className="text-xs font-semibold uppercase tracking-wide text-slate-500">Nodes</h2>
      <p className="text-xs text-slate-500">Drag onto the canvas to add a node.</p>
      <div className="mt-2 flex flex-col gap-2">
        {NODE_KINDS.map(({ kind, label, description }) => (
          <div
            key={kind}
            draggable
            onDragStart={(e) => onDragStart(e, kind)}
            className="cursor-grab rounded-md border border-slate-200 bg-white p-3 shadow-sm transition hover:border-slate-400 active:cursor-grabbing"
          >
            <div className="text-sm font-medium text-slate-800">{label}</div>
            <div className="text-xs text-slate-500">{description}</div>
          </div>
        ))}
      </div>
    </aside>
  )
}
