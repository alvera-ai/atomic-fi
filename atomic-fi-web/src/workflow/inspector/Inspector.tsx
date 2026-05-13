import type { NodeData, WorkflowNode } from '../types'
import { DecisionTableEditor } from './DecisionTableEditor'
import { FunctionEditor } from './FunctionEditor'
import { SchemaEditor } from './SchemaEditor'

type Props = {
  node: WorkflowNode | null
  onChange: (patch: Partial<NodeData>) => void
  onClose: () => void
}

const TYPE_LABEL: Record<string, string> = {
  inputNode: 'Input',
  outputNode: 'Output',
  decisionTableNode: 'Decision Table',
  functionNode: 'Function',
}

const DOT_BY_TYPE: Record<string, string> = {
  inputNode: 'bg-sage',
  outputNode: 'bg-terracotta',
  decisionTableNode: 'bg-violet',
  functionNode: 'bg-amber',
}

export function Inspector({ node, onChange, onClose }: Props) {
  if (!node) return null

  const renderEditor = () => {
    switch (node.type) {
      case 'decisionTableNode':
        return <DecisionTableEditor data={node.data} onChange={onChange} />
      case 'functionNode':
        return <FunctionEditor data={node.data} onChange={onChange} />
      case 'inputNode':
      case 'outputNode':
        return <SchemaEditor data={node.data} onChange={onChange} />
      default:
        return <p className="text-sm text-ink-3">Unknown node type.</p>
    }
  }

  const type = node.type ?? ''
  const widthClass = type === 'decisionTableNode' ? 'w-[560px]' : 'w-[440px]'

  return (
    <aside
      className={`flex h-full shrink-0 flex-col border-l border-rule bg-paper ${widthClass}`}
    >
      <header className="flex items-start justify-between gap-4 px-6 pb-4 pt-5">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <span className={`h-1.5 w-1.5 rounded-full ${DOT_BY_TYPE[type] ?? 'bg-ink-3'}`} />
            <span className="eyebrow">{TYPE_LABEL[type] ?? 'Node'}</span>
          </div>
          <h2 className="mt-1.5 truncate text-[18px] font-semibold leading-tight tracking-tight text-ink">
            {node.data.name || 'Untitled'}
          </h2>
        </div>
        <button
          type="button"
          onClick={onClose}
          className="rounded-md p-1 text-ink-3 transition hover:bg-paper-2 hover:text-ink"
          aria-label="Close inspector"
        >
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
            <path d="M2.5 2.5l9 9M11.5 2.5l-9 9" />
          </svg>
        </button>
      </header>

      <div className="border-t border-rule px-6 py-4">
        <label className="block">
          <span className="eyebrow">Name</span>
          <input
            type="text"
            value={node.data.name}
            onChange={(e) => onChange({ name: e.target.value })}
            className="mt-1.5 w-full border-0 border-b border-rule bg-transparent px-0 py-1 text-[14px] text-ink placeholder:text-ink-4 focus:border-accent focus:outline-none focus:ring-0"
            placeholder="Untitled"
          />
        </label>
      </div>

      <div className="min-h-0 flex-1 overflow-auto border-t border-rule px-6 py-5">
        {renderEditor()}
      </div>
    </aside>
  )
}
