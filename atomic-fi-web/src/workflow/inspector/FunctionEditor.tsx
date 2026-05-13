import type { NodeData } from '../types'
import { CodeEditor } from './CodeEditor'

type Props = {
  data: NodeData
  onChange: (patch: Partial<NodeData>) => void
}

type FunctionContent = { expression?: string }

export function FunctionEditor({ data, onChange }: Props) {
  const content = (data.content ?? {}) as FunctionContent
  const expression = content.expression ?? ''

  return (
    <div className="flex h-full flex-col gap-3">
      <div className="flex items-baseline justify-between">
        <span className="eyebrow">Expression</span>
        <span className="font-mono text-[11px] text-ink-3">
          input → output
        </span>
      </div>
      <CodeEditor
        value={expression}
        onChange={(next) => onChange({ content: { ...content, expression: next } })}
        language="javascript"
        placeholder="input.score >= 720 ? 5.5 : 8.9"
        variant="ink"
        minHeight={280}
      />
      <p className="text-[11px] text-ink-3">
        Returned value flows downstream as this node's output.
      </p>
    </div>
  )
}
