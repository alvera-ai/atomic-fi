import type { NodeProps } from 'reactflow'
import type { NodeData } from '../types'
import { BaseNode } from './BaseNode'

export function InputNode({ id, data }: NodeProps<NodeData>) {
  return (
    <BaseNode
      nodeId={id}
      kind="Input"
      accent="sage"
      name={data.name}
      hasInput={false}
      meta={data.content ? 'Schema attached' : 'No schema'}
    />
  )
}
