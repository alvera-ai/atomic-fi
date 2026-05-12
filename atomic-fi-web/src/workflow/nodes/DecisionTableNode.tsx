import type { NodeProps } from 'reactflow'
import type { NodeData } from '../types'
import { BaseNode } from './BaseNode'

export function DecisionTableNode({ data }: NodeProps<NodeData>) {
  const rowCount = Array.isArray((data.content as { rules?: unknown[] })?.rules)
    ? (data.content as { rules: unknown[] }).rules.length
    : 0
  return (
    <BaseNode title={data.name} subtitle="Decision Table" accent="bg-indigo-100 text-indigo-800">
      {rowCount} rule{rowCount === 1 ? '' : 's'}
    </BaseNode>
  )
}
