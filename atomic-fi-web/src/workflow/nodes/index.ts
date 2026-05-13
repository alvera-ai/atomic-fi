import type { NodeTypes } from 'reactflow'
import { InputNode } from './InputNode'
import { OutputNode } from './OutputNode'
import { DecisionTableNode } from './DecisionTableNode'
import { FunctionNode } from './FunctionNode'

export const nodeTypes: NodeTypes = {
  inputNode: InputNode,
  outputNode: OutputNode,
  decisionTableNode: DecisionTableNode,
  functionNode: FunctionNode,
}
