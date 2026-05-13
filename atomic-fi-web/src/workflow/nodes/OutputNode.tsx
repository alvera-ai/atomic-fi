import type { NodeProps } from 'reactflow'
import type { NodeData } from '../types'
import { BaseNode } from './BaseNode'

export function OutputNode({ id, data }: NodeProps<NodeData>) {
  return (
    <BaseNode
      nodeId={id}
      kind="Output"
      accent="terracotta"
      name={data.name}
      hasOutput={false}
      meta={data.content ? 'Schema attached' : 'No schema'}
    />
  )
}
