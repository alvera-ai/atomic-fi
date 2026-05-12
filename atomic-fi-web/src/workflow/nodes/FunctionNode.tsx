import type { NodeProps } from 'reactflow'
import type { NodeData } from '../types'
import { BaseNode } from './BaseNode'

export function FunctionNode({ data }: NodeProps<NodeData>) {
  const expr = (data.content as { expression?: string })?.expression
  return (
    <BaseNode title={data.name} subtitle="Function" accent="bg-amber-100 text-amber-800">
      <code className="block truncate font-mono text-[11px]">{expr ?? '// empty'}</code>
    </BaseNode>
  )
}
