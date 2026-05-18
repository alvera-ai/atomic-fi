import React from 'react';
import { useCopilotAction } from '@copilotkit/react-core';
import type { DecisionGraphType } from '@gorules/jdm-editor';
import {
  AddNodeArgsSchema,
  UpdateNodeArgsSchema,
  RemoveNodeArgsSchema,
  AddEdgeArgsSchema,
  RemoveEdgeArgsSchema,
  NODE_TYPES,
} from '../node-types';
import { PreviewCard } from '../cards/preview-card';

type SetGraph = React.Dispatch<React.SetStateAction<DecisionGraphType>>;

const newId = (): string =>
  typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : `id_${Date.now()}_${Math.random()}`;

export function useGraphActions(setGraph: SetGraph): void {
  useCopilotAction({
    name: 'add_node',
    description: 'Add a node to the open decision graph.',
    parameters: [
      { name: 'type', type: 'string', enum: [...NODE_TYPES], required: true, description: 'JDM node kind.' },
      { name: 'name', type: 'string', required: true },
      { name: 'content', type: 'object', required: true, description: 'JDM node content for the selected type.' },
      { name: 'position', type: 'object', required: false },
    ],
    renderAndWaitForResponse: ({ args, status, respond }) => {
      const parsed = AddNodeArgsSchema.safeParse(args);
      if (!parsed.success) {
        return (
          <PreviewCard
            title="add_node — invalid args"
            status={status as 'inProgress' | 'executing' | 'complete'}
            summary={<span>Validation failed: {parsed.error.message}</span>}
            onApply={() => respond?.({ accepted: false, reason: parsed.error.message })}
            onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
            applyLabel="Acknowledge"
          />
        );
      }
      const a = parsed.data;
      return (
        <PreviewCard
          title="add_node"
          status={status as 'inProgress' | 'executing' | 'complete'}
          summary={
            <span>
              Add <code className="font-mono">{a.type}</code> node <strong>{a.name}</strong>
              {a.position ? ` at (${a.position.x}, ${a.position.y})` : ''}.
            </span>
          }
          diff={JSON.stringify(a.content, null, 2)}
          onApply={() => {
            const id = newId();
            setGraph((g) => ({
              ...g,
              nodes: [
                ...(g.nodes ?? []),
                {
                  id,
                  type: a.type,
                  name: a.name,
                  position: a.position ?? { x: 0, y: 0 },
                  content: a.content,
                } as NonNullable<DecisionGraphType['nodes']>[number],
              ],
            }));
            respond?.({ accepted: true, node_id: id });
          }}
          onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
        />
      );
    },
  });

  useCopilotAction({
    name: 'update_node',
    description: "Update a node's name, content, or position.",
    parameters: [
      { name: 'node_id', type: 'string', required: true },
      { name: 'patch', type: 'object', required: true },
    ],
    renderAndWaitForResponse: ({ args, status, respond }) => {
      const parsed = UpdateNodeArgsSchema.safeParse(args);
      if (!parsed.success) {
        return (
          <PreviewCard
            title="update_node — invalid args"
            status={status as 'inProgress' | 'executing' | 'complete'}
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
          title="update_node"
          status={status as 'inProgress' | 'executing' | 'complete'}
          summary={
            <span>
              Patch node <code className="font-mono">{a.node_id}</code>.
            </span>
          }
          diff={JSON.stringify(a.patch, null, 2)}
          onApply={() => {
            setGraph((g) => ({
              ...g,
              nodes: (g.nodes ?? []).map((n) =>
                n.id === a.node_id
                  ? ({
                      ...n,
                      ...(a.patch.name !== undefined ? { name: a.patch.name } : {}),
                      ...(a.patch.content !== undefined ? { content: a.patch.content } : {}),
                      ...(a.patch.position !== undefined ? { position: a.patch.position } : {}),
                    } as NonNullable<DecisionGraphType['nodes']>[number])
                  : n,
              ),
            }));
            respond?.({ accepted: true });
          }}
          onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
        />
      );
    },
  });

  useCopilotAction({
    name: 'remove_node',
    description: 'Delete a node (and edges touching it).',
    parameters: [{ name: 'node_id', type: 'string', required: true }],
    renderAndWaitForResponse: ({ args, status, respond }) => {
      const parsed = RemoveNodeArgsSchema.safeParse(args);
      if (!parsed.success) {
        return (
          <PreviewCard
            title="remove_node — invalid args"
            status={status as 'inProgress' | 'executing' | 'complete'}
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
          title="remove_node"
          status={status as 'inProgress' | 'executing' | 'complete'}
          summary={
            <span>
              Remove node <code className="font-mono">{a.node_id}</code> and any edges touching it.
            </span>
          }
          onApply={() => {
            setGraph((g) => ({
              ...g,
              nodes: (g.nodes ?? []).filter((n) => n.id !== a.node_id),
              edges: (g.edges ?? []).filter((e) => e.sourceId !== a.node_id && e.targetId !== a.node_id),
            }));
            respond?.({ accepted: true });
          }}
          onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
        />
      );
    },
  });

  useCopilotAction({
    name: 'add_edge',
    description: 'Connect two nodes.',
    parameters: [
      { name: 'source_id', type: 'string', required: true },
      { name: 'target_id', type: 'string', required: true },
      { name: 'source_handle', type: 'string', required: false },
      { name: 'target_handle', type: 'string', required: false },
    ],
    renderAndWaitForResponse: ({ args, status, respond }) => {
      const parsed = AddEdgeArgsSchema.safeParse(args);
      if (!parsed.success) {
        return (
          <PreviewCard
            title="add_edge — invalid args"
            status={status as 'inProgress' | 'executing' | 'complete'}
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
          title="add_edge"
          status={status as 'inProgress' | 'executing' | 'complete'}
          summary={
            <span>
              Connect <code className="font-mono">{a.source_id}</code> &rarr;{' '}
              <code className="font-mono">{a.target_id}</code>.
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
                  sourceId: a.source_id,
                  targetId: a.target_id,
                  sourceHandle: a.source_handle,
                  targetHandle: a.target_handle,
                } as NonNullable<DecisionGraphType['edges']>[number],
              ],
            }));
            respond?.({ accepted: true, edge_id: id });
          }}
          onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
        />
      );
    },
  });

  useCopilotAction({
    name: 'remove_edge',
    description: 'Disconnect two nodes.',
    parameters: [{ name: 'edge_id', type: 'string', required: true }],
    renderAndWaitForResponse: ({ args, status, respond }) => {
      const parsed = RemoveEdgeArgsSchema.safeParse(args);
      if (!parsed.success) {
        return (
          <PreviewCard
            title="remove_edge — invalid args"
            status={status as 'inProgress' | 'executing' | 'complete'}
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
          status={status as 'inProgress' | 'executing' | 'complete'}
          summary={
            <span>
              Remove edge <code className="font-mono">{a.edge_id}</code>.
            </span>
          }
          onApply={() => {
            setGraph((g) => ({ ...g, edges: (g.edges ?? []).filter((e) => e.id !== a.edge_id) }));
            respond?.({ accepted: true });
          }}
          onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
        />
      );
    },
  });
}
