import { useCallback, useRef } from 'react'
import ReactFlow, {
  Background,
  Controls,
  MiniMap,
  addEdge,
  applyEdgeChanges,
  applyNodeChanges,
  type Connection,
  type EdgeChange,
  type Node,
  type NodeChange,
  type ReactFlowInstance,
} from 'reactflow'
import { nodeTypes } from './nodes'
import type { NodeKind, WorkflowEdge, WorkflowNode } from './types'

type Props = {
  nodes: WorkflowNode[]
  edges: WorkflowEdge[]
  onNodesChange: (nodes: WorkflowNode[]) => void
  onEdgesChange: (edges: WorkflowEdge[]) => void
  onOpenNode: (nodeId: string) => void
}

let idCounter = 1
const nextId = () => `n_${Date.now().toString(36)}_${idCounter++}`

export function Canvas({
  nodes,
  edges,
  onNodesChange,
  onEdgesChange,
  onOpenNode,
}: Props) {
  const rfInstance = useRef<ReactFlowInstance | null>(null)

  const handleNodesChange = useCallback(
    (changes: NodeChange[]) => onNodesChange(applyNodeChanges(changes, nodes) as WorkflowNode[]),
    [nodes, onNodesChange],
  )

  const handleEdgesChange = useCallback(
    (changes: EdgeChange[]) => onEdgesChange(applyEdgeChanges(changes, edges)),
    [edges, onEdgesChange],
  )

  const onConnect = useCallback(
    (params: Connection) => onEdgesChange(addEdge({ ...params, id: nextId() }, edges)),
    [edges, onEdgesChange],
  )

  const onDragOver = useCallback((event: React.DragEvent) => {
    event.preventDefault()
    event.dataTransfer.dropEffect = 'move'
  }, [])

  const onDrop = useCallback(
    (event: React.DragEvent) => {
      event.preventDefault()
      const kind = event.dataTransfer.getData('application/x-jdm-node') as NodeKind
      if (!kind || !rfInstance.current) return
      const position = rfInstance.current.screenToFlowPosition({
        x: event.clientX,
        y: event.clientY,
      })
      const newNode: WorkflowNode = {
        id: nextId(),
        type: kind,
        position,
        data: { name: defaultName(kind), content: defaultContent(kind) },
      }
      onNodesChange(nodes.concat(newNode))
    },
    [nodes, onNodesChange],
  )

  const handleNodeDoubleClick = useCallback(
    (_event: React.MouseEvent, node: Node) => onOpenNode(node.id),
    [onOpenNode],
  )

  return (
    <div className="h-full w-full" onDragOver={onDragOver} onDrop={onDrop}>
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={handleNodesChange}
        onEdgesChange={handleEdgesChange}
        onConnect={onConnect}
        onNodeDoubleClick={handleNodeDoubleClick}
        onInit={(instance) => (rfInstance.current = instance)}
        nodeTypes={nodeTypes}
        fitView
      >
        <Background gap={16} />
        <MiniMap pannable zoomable />
        <Controls />
      </ReactFlow>
    </div>
  )
}

function defaultName(kind: NodeKind): string {
  switch (kind) {
    case 'inputNode': return 'Input'
    case 'outputNode': return 'Output'
    case 'decisionTableNode': return 'Decision Table'
    case 'functionNode': return 'Function'
  }
}

function defaultContent(kind: NodeKind): unknown {
  switch (kind) {
    case 'decisionTableNode':
      return {
        hitPolicy: 'first',
        inputs: [{ id: 'in_1', type: 'expression', name: 'Input', field: 'input.value' }],
        outputs: [{ id: 'out_1', type: 'expression', name: 'Output', field: 'output.value' }],
        rules: [],
      }
    case 'functionNode':
      return { expression: '' }
    default:
      return undefined
  }
}
