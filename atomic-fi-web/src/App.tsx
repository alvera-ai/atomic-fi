import { useCallback, useEffect, useMemo, useState } from 'react'
import { ReactFlowProvider } from 'reactflow'
import { Toolbar } from './workflow/Toolbar'
import { NodePalette } from './workflow/NodePalette'
import { Canvas } from './workflow/Canvas'
import { Inspector } from './workflow/inspector/Inspector'
import { NodeEditContext } from './workflow/nodes/EditContext'
import type { NodeData, WorkflowEdge, WorkflowNode } from './workflow/types'
import {
  downloadJson,
  parseWorkflow,
  readJsonFile,
  rulesFileToGraph,
  workflowToRulesFile,
} from './workflow/serialize'

const SAMPLE_PATH = '/example-rules.json'
const SAMPLE_NAME = 'de_minimis'

export default function App() {
  const [name, setName] = useState(SAMPLE_NAME)
  const [nodes, setNodes] = useState<WorkflowNode[]>([])
  const [edges, setEdges] = useState<WorkflowEdge[]>([])
  const [editingNodeId, setEditingNodeId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetch(SAMPLE_PATH)
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (!data) return
        const parsed = parseWorkflow(data)
        if (!parsed.ok) return
        const graph = rulesFileToGraph(parsed.value)
        setNodes(graph.nodes)
        setEdges(graph.edges)
      })
      .catch(() => {})
  }, [])

  const handleLoad = useCallback(async (file: File) => {
    setError(null)
    try {
      const raw = await readJsonFile(file)
      const parsed = parseWorkflow(raw)
      if (!parsed.ok) {
        setError(parsed.error)
        return
      }
      const graph = rulesFileToGraph(parsed.value)
      setName(file.name.replace(/\.json$/i, ''))
      setNodes(graph.nodes)
      setEdges(graph.edges)
      setEditingNodeId(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to read file')
    }
  }, [])

  const handleSave = useCallback(() => {
    const rulesFile = workflowToRulesFile(nodes, edges)
    downloadJson(name || 'untitled-workflow', rulesFile)
  }, [edges, name, nodes])

  const handleReset = useCallback(() => {
    setName('untitled-workflow')
    setNodes([])
    setEdges([])
    setEditingNodeId(null)
    setError(null)
  }, [])

  const patchNode = useCallback(
    (id: string, patch: Partial<NodeData>) => {
      setNodes((current) =>
        current.map((n) =>
          n.id === id ? { ...n, data: { ...n.data, ...patch } } : n,
        ),
      )
    },
    [],
  )

  const editingNode = useMemo(
    () => nodes.find((n) => n.id === editingNodeId) ?? null,
    [nodes, editingNodeId],
  )

  useEffect(() => {
    if (!editingNodeId) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setEditingNodeId(null)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [editingNodeId])

  return (
    <div className="flex h-full flex-col bg-slate-100">
      <Toolbar
        name={name}
        onNameChange={setName}
        onLoad={handleLoad}
        onSave={handleSave}
        onReset={handleReset}
      />
      {error && (
        <div className="border-b border-rose-200 bg-rose-50 px-4 py-2 text-sm text-rose-700">
          {error}
        </div>
      )}
      <div className="flex min-h-0 flex-1">
        <NodePalette />
        <main className="min-h-0 flex-1">
          <ReactFlowProvider>
            <NodeEditContext.Provider value={setEditingNodeId}>
              <Canvas
                nodes={nodes}
                edges={edges}
                onNodesChange={setNodes}
                onEdgesChange={setEdges}
                onOpenNode={setEditingNodeId}
              />
            </NodeEditContext.Provider>
          </ReactFlowProvider>
        </main>
        <Inspector
          node={editingNode}
          onChange={(patch) => editingNode && patchNode(editingNode.id, patch)}
          onClose={() => setEditingNodeId(null)}
        />
      </div>
    </div>
  )
}
