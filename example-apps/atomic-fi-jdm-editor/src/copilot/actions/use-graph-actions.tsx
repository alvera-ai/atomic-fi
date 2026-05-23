import React from 'react';
import { useHumanInTheLoop } from '@copilotkit/react-core/v2';
import type { DecisionGraphType } from '@gorules/jdm-editor';
import {
  AddNodeArgsSchema,
  UpdateNodeArgsSchema,
  RemoveNodeArgsSchema,
  AddEdgeArgsSchema,
  RemoveEdgeArgsSchema,
} from '../node-types';
import {
  AddNodeToolParams,
  UpdateNodeToolParams,
  RemoveNodeToolParams,
  AddEdgeToolParams,
  RemoveEdgeToolParams,
} from '../tool-params';
import { PreviewCard } from '../cards/preview-card';

type SetGraph = React.Dispatch<React.SetStateAction<DecisionGraphType>>;
type Node = NonNullable<DecisionGraphType['nodes']>[number];

type GraphActionsArgs = {
  setGraph: SetGraph;
  // Always-current snapshot of the graph. Used by render callbacks to look
  // up node names from ids without baking a stale graph into the JSX.
  graphRef: React.RefObject<DecisionGraphType>;
  // Tell the page a mutation just landed so it can bump its revision counter
  // (the canvas-driven `handleChange` does this for human edits; agent edits
  // need an equivalent hook so the dirty indicator and save-state stay in
  // sync with reality).
  onMutated: () => void;
};

const newId = (): string =>
  typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : `id_${Date.now()}_${Math.random()}`;

// Layout constants — mirror jdm-cheatsheet's "~280px between nodes" convention.
const HORIZONTAL_GAP = 280;
const Y_CENTER = 160;
const X_INPUT = 100;

// Place new nodes along a left-to-right flow so they don't overlap when the
// agent omits `position`. inputNode goes on the far left; outputNode lands to
// the right of the rightmost existing non-output node; everything else
// cascades in the middle.
function autoPosition(existingNodes: readonly Node[], type: string): { x: number; y: number } {
  if (type === 'inputNode') {
    return { x: X_INPUT, y: Y_CENTER };
  }
  if (type === 'outputNode') {
    const nonOutputMaxX = existingNodes
      .filter((n) => n.type !== 'outputNode')
      .reduce((max, n) => Math.max(max, n.position?.x ?? 0), X_INPUT);
    return { x: nonOutputMaxX + HORIZONTAL_GAP, y: Y_CENTER };
  }
  // Middle nodes (decisionTable, expression, function, switch, custom,
  // decision): cascade just after the last middle node.
  const middleNodes = existingNodes.filter((n) => n.type !== 'inputNode' && n.type !== 'outputNode');
  const baseX = X_INPUT + HORIZONTAL_GAP;
  return { x: baseX + HORIZONTAL_GAP * middleNodes.length, y: Y_CENTER };
}

// CopilotKit v2 graph tools. Each is Human-in-the-Loop: the agent proposes,
// a PreviewCard renders, the user Applies/Rejects, and the user's decision is
// the tool result. `deps: []` registers each tool once — the render closures
// read mutable editor state through `graphRef`/stable setters, so they always
// see the live graph. See docs/copilot-architecture.md §5.
export function useGraphActions({ setGraph, graphRef, onMutated }: GraphActionsArgs): void {
  // Resolve either an actual node id or a node name to the canonical id.
  // The agent often emits add_edge args before it knows the real generated
  // ids (all tool calls in a turn run in parallel, so add_node results
  // haven't been delivered yet) and instead passes the node's NAME. Accept
  // both forms so a dependent tool call still works.
  const resolveNodeId = (idOrName: string): string | undefined => {
    const nodes = graphRef.current.nodes ?? [];
    return nodes.find((n) => n.id === idOrName)?.id ?? nodes.find((n) => n.name === idOrName)?.id;
  };

  const lookupNodeName = (idOrName: string): string => {
    const nodes = graphRef.current.nodes ?? [];
    const node = nodes.find((n) => n.id === idOrName) ?? nodes.find((n) => n.name === idOrName);
    if (node?.name) return `${node.name}`;
    // Fallback: show the raw value so the user can at least diff against
    // the graph. 8-char slicing was misleading — it looked like a real
    // truncated id but was actually a hallucinated reference.
    return `(unresolved: ${idOrName})`;
  };

  useHumanInTheLoop(
    {
      name: 'add_node',
      description: 'Add a node to the open decision graph.',
      parameters: AddNodeToolParams,
      render: ({ args, status, respond }) => {
        const parsed = AddNodeArgsSchema.safeParse(args);
        if (!parsed.success) {
          return (
            <PreviewCard
              title="add_node — invalid args"
              status={status}
              summary={<span>Validation failed: {parsed.error.message}</span>}
              onApply={() => respond?.({ accepted: false, reason: parsed.error.message })}
              onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
              applyLabel="Acknowledge"
            />
          );
        }
        const a = parsed.data;
        // Reject duplicate-name adds — when the agent realizes an earlier node
        // had a typo, it should call update_node, not re-add. Same-name nodes
        // create ambiguous edge targets and break ZenRule's compile step.
        const existingWithSameName = (graphRef.current.nodes ?? []).find((n) => n.name === a.name);
        if (existingWithSameName) {
          return (
            <PreviewCard
              title="add_node — duplicate name"
              status={status}
              summary={
                <span>
                  A node named <strong>{a.name}</strong> already exists (id{' '}
                  <code className="font-mono">{existingWithSameName.id.slice(0, 8)}</code>). Use{' '}
                  <code className="font-mono">update_node</code> to modify it instead of adding a duplicate.
                </span>
              }
              onApply={() =>
                respond?.({
                  accepted: false,
                  reason: `Duplicate node name "${a.name}". Use update_node({ node_id: "${existingWithSameName.id}", patch: { ... } }) to modify the existing node.`,
                  existing_node_id: existingWithSameName.id,
                })
              }
              onReject={() =>
                respond?.({
                  accepted: false,
                  reason: `Duplicate node name "${a.name}"; user rejected.`,
                })
              }
              applyLabel="Acknowledge"
            />
          );
        }
        return (
          <PreviewCard
            title="add_node"
            status={status}
            summary={
              <span>
                Add <code className="font-mono">{a.type}</code> node <strong>{a.name}</strong>
                {a.position ? ` at (${a.position.x}, ${a.position.y})` : ''}.
              </span>
            }
            diff={JSON.stringify(a.content, null, 2)}
            onApply={() => {
              const id = newId();
              setGraph((g) => {
                const existing = g.nodes ?? [];
                const position = a.position ?? autoPosition(existing, a.type);
                const isContentless = a.type === 'inputNode' || a.type === 'outputNode';
                const node = {
                  id,
                  type: a.type,
                  name: a.name,
                  position,
                  ...(isContentless ? {} : { content: a.content ?? {} }),
                } as Node;
                return { ...g, nodes: [...existing, node] };
              });
              onMutated();
              respond?.({ accepted: true, node_id: id });
            }}
            onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
          />
        );
      },
    },
    [],
  );

  useHumanInTheLoop(
    {
      name: 'update_node',
      description:
        "Update a node's name, content, or position. Pass the changes either nested under `patch` (canonical) OR as top-level shorthand — both are accepted. Provide ONLY the fields you want to change; omitted fields are preserved. **Use this to fix typos and bugs in a node's content — DO NOT remove and re-add.**",
      parameters: UpdateNodeToolParams,
      render: ({ args, status, respond }) => {
        const parsed = UpdateNodeArgsSchema.safeParse(args);
        if (!parsed.success) {
          return (
            <PreviewCard
              title="update_node — invalid args"
              status={status}
              summary={<span>{parsed.error.message}</span>}
              onApply={() => respond?.({ accepted: false, reason: parsed.error.message })}
              onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
              applyLabel="Acknowledge"
            />
          );
        }
        const a = parsed.data;
        const resolvedId = resolveNodeId(a.node_id);
        if (!resolvedId) {
          return (
            <PreviewCard
              title="update_node — node not found"
              status={status}
              summary={
                <span>
                  No node with id or name <code className="font-mono">{a.node_id}</code>. Existing:{' '}
                  {(graphRef.current.nodes ?? []).map((n) => `${n.name}`).join(', ') || '(none)'}.
                </span>
              }
              onApply={() =>
                respond?.({
                  accepted: false,
                  reason: `update_node target "${a.node_id}" matches no node. Pass either the id (from add_node's response) or the node's exact name.`,
                  existing_nodes: (graphRef.current.nodes ?? []).map((n) => ({ id: n.id, name: n.name })),
                })
              }
              onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
              applyLabel="Acknowledge"
            />
          );
        }
        return (
          <PreviewCard
            title="update_node"
            status={status}
            summary={
              <span>
                Patch node <strong>{lookupNodeName(resolvedId)}</strong>.
              </span>
            }
            diff={JSON.stringify(a.patch, null, 2)}
            onApply={() => {
              setGraph((g) => ({
                ...g,
                nodes: (g.nodes ?? []).map((n) =>
                  n.id === resolvedId
                    ? ({
                        ...n,
                        ...(a.patch.name !== undefined ? { name: a.patch.name } : {}),
                        ...(a.patch.content !== undefined ? { content: a.patch.content } : {}),
                        ...(a.patch.position !== undefined ? { position: a.patch.position } : {}),
                      } as NonNullable<DecisionGraphType['nodes']>[number])
                    : n,
                ),
              }));
              onMutated();
              respond?.({ accepted: true });
            }}
            onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
          />
        );
      },
    },
    [],
  );

  useHumanInTheLoop(
    {
      name: 'remove_node',
      description: 'Delete a node (and edges touching it). Use sparingly — prefer update_node for fixes.',
      parameters: RemoveNodeToolParams,
      render: ({ args, status, respond }) => {
        const parsed = RemoveNodeArgsSchema.safeParse(args);
        if (!parsed.success) {
          return (
            <PreviewCard
              title="remove_node — invalid args"
              status={status}
              summary={<span>{parsed.error.message}</span>}
              onApply={() => respond?.({ accepted: false, reason: parsed.error.message })}
              onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
              applyLabel="Acknowledge"
            />
          );
        }
        const a = parsed.data;
        const resolvedRemoveId = resolveNodeId(a.node_id);
        if (!resolvedRemoveId) {
          return (
            <PreviewCard
              title="remove_node — node not found"
              status={status}
              summary={
                <span>
                  No node with id or name <code className="font-mono">{a.node_id}</code>.
                </span>
              }
              onApply={() =>
                respond?.({ accepted: false, reason: `remove_node target "${a.node_id}" matches no node.` })
              }
              onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
              applyLabel="Acknowledge"
            />
          );
        }
        return (
          <PreviewCard
            title="remove_node"
            status={status}
            summary={
              <span>
                Remove node <strong>{lookupNodeName(resolvedRemoveId)}</strong> and any edges touching it.
              </span>
            }
            onApply={() => {
              setGraph((g) => ({
                ...g,
                nodes: (g.nodes ?? []).filter((n) => n.id !== resolvedRemoveId),
                edges: (g.edges ?? []).filter(
                  (e) => e.sourceId !== resolvedRemoveId && e.targetId !== resolvedRemoveId,
                ),
              }));
              onMutated();
              respond?.({ accepted: true });
            }}
            onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
          />
        );
      },
    },
    [],
  );

  useHumanInTheLoop(
    {
      name: 'add_edge',
      description:
        "Connect two nodes. source_id and target_id accept EITHER the real node id returned by add_node OR the node's exact name. Use the name when you're emitting add_edge in the same turn as the add_node calls it depends on (the real ids aren't available yet in that case).",
      parameters: AddEdgeToolParams,
      render: ({ args, status, respond }) => {
        const parsed = AddEdgeArgsSchema.safeParse(args);
        if (!parsed.success) {
          return (
            <PreviewCard
              title="add_edge — invalid args"
              status={status}
              summary={<span>{parsed.error.message}</span>}
              onApply={() => respond?.({ accepted: false, reason: parsed.error.message })}
              onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
              applyLabel="Acknowledge"
            />
          );
        }
        const a = parsed.data;
        const sourceLabel = lookupNodeName(a.source_id);
        const targetLabel = lookupNodeName(a.target_id);
        const sourceResolved = resolveNodeId(a.source_id);
        const targetResolved = resolveNodeId(a.target_id);
        const unresolved = !sourceResolved || !targetResolved;
        if (unresolved) {
          const reasons: string[] = [];
          if (!sourceResolved) reasons.push(`source "${a.source_id}" matches no node id or name`);
          if (!targetResolved) reasons.push(`target "${a.target_id}" matches no node id or name`);
          return (
            <PreviewCard
              title="add_edge — endpoint not found"
              status={status}
              summary={
                <span>
                  Cannot create edge: {reasons.join(' and ')}. Existing nodes:{' '}
                  {(graphRef.current.nodes ?? []).map((n) => `${n.name}`).join(', ') || '(none yet)'}.
                </span>
              }
              onApply={() =>
                respond?.({
                  accepted: false,
                  reason: `Edge endpoints don't resolve. ${reasons.join('; ')}. Call add_edge with either real node ids (returned from add_node) or the exact node names (case-sensitive).`,
                  existing_nodes: (graphRef.current.nodes ?? []).map((n) => ({ id: n.id, name: n.name })),
                })
              }
              onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
              applyLabel="Acknowledge"
            />
          );
        }
        return (
          <PreviewCard
            title="add_edge"
            status={status}
            summary={
              <span>
                Connect <strong>{sourceLabel}</strong> &rarr; <strong>{targetLabel}</strong>.
              </span>
            }
            onApply={() => {
              const id = newId();
              setGraph((g) => ({
                ...g,
                edges: [
                  ...(g.edges ?? []),
                  {
                    id,
                    sourceId: sourceResolved,
                    targetId: targetResolved,
                    sourceHandle: a.source_handle,
                    targetHandle: a.target_handle,
                  } as NonNullable<DecisionGraphType['edges']>[number],
                ],
              }));
              onMutated();
              respond?.({ accepted: true, edge_id: id });
            }}
            onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
          />
        );
      },
    },
    [],
  );

  useHumanInTheLoop(
    {
      name: 'remove_edge',
      description: 'Disconnect two nodes.',
      parameters: RemoveEdgeToolParams,
      render: ({ args, status, respond }) => {
        const parsed = RemoveEdgeArgsSchema.safeParse(args);
        if (!parsed.success) {
          return (
            <PreviewCard
              title="remove_edge — invalid args"
              status={status}
              summary={<span>{parsed.error.message}</span>}
              onApply={() => respond?.({ accepted: false, reason: parsed.error.message })}
              onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
              applyLabel="Acknowledge"
            />
          );
        }
        const a = parsed.data;
        return (
          <PreviewCard
            title="remove_edge"
            status={status}
            summary={
              <span>
                Remove edge <code className="font-mono">{a.edge_id}</code>.
              </span>
            }
            onApply={() => {
              setGraph((g) => ({ ...g, edges: (g.edges ?? []).filter((e) => e.id !== a.edge_id) }));
              onMutated();
              respond?.({ accepted: true });
            }}
            onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
          />
        );
      },
    },
    [],
  );
}
