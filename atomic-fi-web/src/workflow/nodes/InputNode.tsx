import type { NodeProps } from 'reactflow'
import type { NodeData } from '../types'
import { BaseNode } from './BaseNode'

export function InputNode({ data }: NodeProps<NodeData>) {
  return (
    <BaseNode
      title={data.name}
      subtitle="Input"
      accent="bg-emerald-100 text-emerald-800"
      hasInput={false}
    />
  )
}
