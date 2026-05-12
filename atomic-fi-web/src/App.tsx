import { useCallback, useEffect, useState } from 'react'
import { ReactFlowProvider } from 'reactflow'
import { Toolbar } from './workflow/Toolbar'
import { NodePalette } from './workflow/NodePalette'
import { Canvas } from './workflow/Canvas'
import type { WorkflowEdge, WorkflowNode } from './workflow/types'
import {
  downloadJson,
  parseWorkflow,
  readJsonFile,
  rulesFileToGraph,
  workflowToRulesFile,
} from './workflow/serialize'

const EMPTY: { nodes: WorkflowNode[]; edges: WorkflowEdge[] } = { nodes: [], edges: [] }
const SAMPLE_PATH = '/example-rules.json'
const SAMPLE_NAME = 'de_minimis'

export default function App() {
  const [name, setName] = useState(SAMPLE_NAME)
  const [graph, setGraph] = useState(EMPTY)
  const [graphKey, setGraphKey] = useState(0)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetch(SAMPLE_PATH)
      .then((r) => (r.ok ? r.json() : null))
      .then((data) => {
        if (!data) return
        const parsed = parseWorkflow(data)
        if (!parsed.ok) return
        setGraph(rulesFileToGraph(parsed.value))
        setGraphKey((k) => k + 1)
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
      setName(file.name.replace(/\.json$/i, ''))
      setGraph(rulesFileToGraph(parsed.value))
      setGraphKey((k) => k + 1)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to read file')
    }
  }, [])

  const handleSave = useCallback(() => {
    const rulesFile = workflowToRulesFile(graph.nodes, graph.edges)
    downloadJson(name || 'untitled-workflow', rulesFile)
  }, [graph.edges, graph.nodes, name])

  const handleReset = useCallback(() => {
    setName('untitled-workflow')
    setGraph(EMPTY)
    setGraphKey((k) => k + 1)
    setError(null)
  }, [])

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
            <Canvas
              key={graphKey}
              initialNodes={graph.nodes}
              initialEdges={graph.edges}
              onGraphChange={(nodes, edges) => setGraph({ nodes, edges })}
            />
          </ReactFlowProvider>
        </main>
      </div>
    </div>
  )
}
