import type { NodeProps } from 'reactflow'
import type { NodeData } from '../types'
import { BaseNode } from './BaseNode'

export function FunctionNode({ id, data }: NodeProps<NodeData>) {
  const expr = (data.content as { expression?: string })?.expression ?? ''
  return (
    <BaseNode
      nodeId={id}
      kind="Function"
      accent="amber"
      name={data.name}
      meta={null}
      body={
        <code className="block truncate font-mono text-[11px] text-ink-2">
          {expr.trim() || <span className="text-ink-3">// empty</span>}
        </code>
      }
    />
  )
}
