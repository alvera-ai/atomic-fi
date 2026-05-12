import type {
  RulesFile,
  RulesFileEdge,
  RulesFileNode,
  WorkflowEdge,
  WorkflowNode,
} from './types'

export type ParseResult =
  | { ok: true; value: RulesFile }
  | { ok: false; error: string }

/**
 * Validate and parse a loaded JSON blob into a RulesFile.
 *
 * This is the most interesting decision point of the POC:
 *   - Permissive parsing keeps the demo flowing but lets bad data crash
 *     the canvas downstream (e.g. a node with no `type`).
 *   - Strict parsing surfaces issues immediately but rejects files that
 *     are "mostly fine" (a missing edge id, a stray field).
 *
 * Goal: return a clear, user-facing message on failure. Reject anything
 * that would break React Flow rendering; tolerate harmless extras.
 *
 * Validate at minimum:
 *   1. `value` is a plain object
 *   2. `value.contentType` matches the expected decision-graph identifier
 *   3. `value.nodes` is an array; each node has id (string), type (NodeKind),
 *      name (string), position {x,y} (numbers)
 *   4. `value.edges` is an array; each edge has id, sourceId, targetId (strings)
 *
 * Return { ok: false, error } with a message that names the first problem.
 */
export function parseWorkflow(value: unknown): ParseResult {
  // TODO(you): implement real validation here. ~8 lines.
  // Walk the shape, return { ok: false, error: '...' } on the first
  // missing/invalid field, otherwise { ok: true, value: ... }.
  //
  // The minimal stub below only checks that the payload is an object,
  // so downstream code can already use the discriminated-union narrowing.
  if (!value || typeof value !== 'object') {
    return { ok: false, error: 'Expected a JSON object at the top level.' }
  }
  return { ok: true, value: value as RulesFile }
}

export function workflowToRulesFile(
  nodes: WorkflowNode[],
  edges: WorkflowEdge[],
): RulesFile {
  return {
    contentType: 'application/vnd.gorules.decision',
    nodes: nodes.map<RulesFileNode>((n) => ({
      id: n.id,
      type: (n.type ?? 'functionNode') as RulesFileNode['type'],
      name: n.data.name,
      position: n.position,
      ...(n.data.content !== undefined ? { content: n.data.content } : {}),
    })),
    edges: edges.map<RulesFileEdge>((e) => ({
      id: e.id,
      type: 'edge',
      sourceId: e.source,
      targetId: e.target,
    })),
  }
}

export function rulesFileToGraph(
  file: RulesFile,
): { nodes: WorkflowNode[]; edges: WorkflowEdge[] } {
  return {
    nodes: file.nodes.map<WorkflowNode>((n) => ({
      id: n.id,
      type: n.type,
      position: n.position,
      data: { name: n.name, content: n.content },
    })),
    edges: file.edges.map<WorkflowEdge>((e) => ({
      id: e.id,
      source: e.sourceId,
      target: e.targetId,
    })),
  }
}

export function downloadJson(filename: string, payload: unknown): void {
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename.endsWith('.json') ? filename : `${filename}.json`
  document.body.appendChild(a)
  a.click()
  a.remove()
  URL.revokeObjectURL(url)
}

export async function readJsonFile(file: File): Promise<unknown> {
  const text = await file.text()
  return JSON.parse(text)
}
