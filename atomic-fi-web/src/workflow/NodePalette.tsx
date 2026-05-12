import { NODE_KINDS } from './types'
import type { NodeKind } from './types'

const dotByKind: Record<NodeKind, string> = {
  inputNode: 'bg-sage',
  outputNode: 'bg-terracotta',
  decisionTableNode: 'bg-violet',
  functionNode: 'bg-amber',
}

export function NodePalette() {
  const onDragStart = (event: React.DragEvent, kind: NodeKind) => {
    event.dataTransfer.setData('application/x-rule-node', kind)
    event.dataTransfer.effectAllowed = 'move'
  }

  return (
    <aside className="flex h-full w-64 shrink-0 flex-col border-r border-rule bg-paper-2">
      <div className="px-5 pb-2 pt-5">
        <h2 className="eyebrow">Palette</h2>
        <p className="mt-1 text-[12px] leading-snug text-ink-3">
          Drag a node onto the canvas to extend the decision graph.
        </p>
      </div>

      <div className="mt-2 flex flex-col">
        {NODE_KINDS.map(({ kind, label, description }) => (
          <div
            key={kind}
            draggable
            onDragStart={(e) => onDragStart(e, kind)}
            className="group cursor-grab border-t border-rule px-5 py-3 transition-colors hover:bg-paper-3 active:cursor-grabbing"
          >
            <div className="flex items-center gap-2.5">
              <span className={`h-1.5 w-1.5 rounded-full ${dotByKind[kind]}`} />
              <span className="text-[13px] font-medium text-ink">{label}</span>
            </div>
            <p className="mt-1 pl-[15px] text-[11.5px] leading-snug text-ink-3">
              {description}
            </p>
          </div>
        ))}
        <div className="border-t border-rule" />
      </div>
    </aside>
  )
}
