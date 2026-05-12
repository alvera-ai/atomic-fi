import { useCallback, useRef } from 'react'
import ReactFlow, {
  Background,
  Controls,
  MiniMap,
  addEdge,
  useEdgesState,
  useNodesState,
  type Connection,
  type ReactFlowInstance,
} from 'reactflow'
import { nodeTypes } from './nodes'
import type { NodeKind, WorkflowEdge, WorkflowNode } from './types'

type Props = {
  initialNodes: WorkflowNode[]
  initialEdges: WorkflowEdge[]
  onGraphChange: (nodes: WorkflowNode[], edges: WorkflowEdge[]) => void
}

let idCounter = 1
const nextId = () => `n_${Date.now().toString(36)}_${idCounter++}`

export function Canvas({ initialNodes, initialEdges, onGraphChange }: Props) {
  const [nodes, setNodes, onNodesChange] = useNodesState<WorkflowNode['data']>(initialNodes)
  const [edges, setEdges, onEdgesChange] = useEdgesState(initialEdges)
  const wrapperRef = useRef<HTMLDivElement>(null)
  const rfInstance = useRef<ReactFlowInstance | null>(null)

  const emit = useCallback(
    (n: WorkflowNode[], e: WorkflowEdge[]) => onGraphChange(n, e),
    [onGraphChange],
  )

  const onConnect = useCallback(
    (params: Connection) => {
      setEdges((eds) => {
        const next = addEdge({ ...params, id: nextId() }, eds)
        emit(nodes, next)
        return next
      })
    },
    [emit, nodes, setEdges],
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
        data: { name: defaultName(kind) },
      }
      setNodes((nds) => {
        const next = nds.concat(newNode)
        emit(next, edges)
        return next
      })
    },
    [edges, emit, setNodes],
  )

  return (
    <div ref={wrapperRef} className="h-full w-full" onDragOver={onDragOver} onDrop={onDrop}>
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={(changes) => {
          onNodesChange(changes)
          emit(nodes, edges)
        }}
        onEdgesChange={(changes) => {
          onEdgesChange(changes)
          emit(nodes, edges)
        }}
        onConnect={onConnect}
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
