import type { NodeProps } from 'reactflow'
import type { NodeData } from '../types'
import { BaseNode } from './BaseNode'

export function OutputNode({ data }: NodeProps<NodeData>) {
  return (
    <BaseNode
      title={data.name}
      subtitle="Output"
      accent="bg-rose-100 text-rose-800"
      hasOutput={false}
    />
  )
}
