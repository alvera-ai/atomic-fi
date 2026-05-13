import type { NodeProps } from 'reactflow'
import type { NodeData } from '../types'
import { BaseNode } from './BaseNode'

type Cell = { id: string; name: string }
type DT = { hitPolicy?: string; inputs?: Cell[]; outputs?: Cell[]; rules?: unknown[] }

export function DecisionTableNode({ id, data }: NodeProps<NodeData>) {
  const c = (data.content ?? {}) as DT
  const inputs = c.inputs?.length ?? 0
  const outputs = c.outputs?.length ?? 0
  const rules = c.rules?.length ?? 0
  return (
    <BaseNode
      nodeId={id}
      kind="Decision Table"
      accent="violet"
      name={data.name}
      meta={
        <span className="font-mono">
          {rules} {rules === 1 ? 'rule' : 'rules'} · {inputs} in · {outputs} out
        </span>
      }
      body={
        c.hitPolicy ? (
          <span>
            hit policy <span className="font-mono text-ink-2">{c.hitPolicy}</span>
          </span>
        ) : null
      }
    />
  )
}
