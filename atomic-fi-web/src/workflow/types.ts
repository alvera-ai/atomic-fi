import type { Edge, Node } from 'reactflow'

export type NodeKind =
  | 'inputNode'
  | 'outputNode'
  | 'decisionTableNode'
  | 'functionNode'

export type NodeData = {
  name: string
  content?: unknown
}

export type WorkflowNode = Node<NodeData>
export type WorkflowEdge = Edge

/**
 * On-disk format — GoRules JDM (JSON Decision Model).
 * Matches what the Elixir backend persists under priv/zenrule/.
 */
export type RulesFile = {
  contentType: 'application/vnd.gorules.decision'
  nodes: RulesFileNode[]
  edges: RulesFileEdge[]
}

export type RulesFileNode = {
  id: string
  type: NodeKind
  name: string
  position: { x: number; y: number }
  content?: unknown
}

export type RulesFileEdge = {
  id: string
  type: 'edge'
  sourceId: string
  targetId: string
}

export const NODE_KINDS: { kind: NodeKind; label: string; description: string }[] = [
  { kind: 'inputNode', label: 'Input', description: 'Entry point of the decision graph' },
  { kind: 'decisionTableNode', label: 'Decision Table', description: 'Evaluate rules in tabular form' },
  { kind: 'functionNode', label: 'Function', description: 'Run a JS expression' },
  { kind: 'outputNode', label: 'Output', description: 'Terminal result of the graph' },
]
