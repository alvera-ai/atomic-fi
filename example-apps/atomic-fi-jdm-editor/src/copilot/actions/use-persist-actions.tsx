import React from 'react';
import { useCopilotAction } from '@copilotkit/react-core';
import { useNavigate } from 'react-router-dom';
import type { DecisionGraphType } from '@gorules/jdm-editor';
import { DirectedGraph } from 'graphology';
import { hasCycle } from 'graphology-dag';
import { CreateRuleArgsSchema, DeleteRuleArgsSchema, OpenRuleArgsSchema } from '../node-types';
import { PersistCard } from '../cards/persist-card';
import { DestructiveCard } from '../cards/destructive-card';
import { deleteRule, saveRule, type RuleType } from '../../helpers/rules-api';

const DECISION_CONTENT_TYPE = 'application/vnd.gorules.decision';

const isCyclic = (graph: DecisionGraphType): boolean => {
  const g = new DirectedGraph();
  (graph.edges ?? []).forEach((e) => {
    if (e.sourceId && e.targetId) g.mergeEdge(e.sourceId, e.targetId);
  });
  return hasCycle(g);
};

type Args = {
  ruleType: RuleType;
  filename: string;
  dirty: boolean;
  graph: DecisionGraphType;
  onSaved: () => void;
  refreshExistingRules: () => Promise<void>;
};

export function usePersistActions(args: Args): void {
  const navigate = useNavigate();
  const { ruleType, filename, dirty, graph, onSaved, refreshExistingRules } = args;

  useCopilotAction({
    name: 'save_rule',
    description:
      'Persist the current open graph to disk. Uses the current rule_type and filename from current_rule_meta.',
    parameters: [],
    renderAndWaitForResponse: ({ status, respond }) => {
      const cyclic = isCyclic(graph);
      return (
        <PersistCard
          title="save_rule"
          status={status as 'inProgress' | 'executing' | 'complete'}
          sideEffectLabel="Save"
          summary={
            <span>
              {cyclic
                ? 'Graph has a cycle — refuse to save.'
                : dirty
                  ? `Will write ${filename} (${(graph.nodes ?? []).length} nodes, ${(graph.edges ?? []).length} edges) to disk.`
                  : 'No unsaved changes; save will be a no-op.'}
            </span>
          }
          onApply={async () => {
            if (cyclic) {
              respond?.({ accepted: false, reason: 'Graph has a cycle; refuse to save.' });
              return;
            }
            try {
              await saveRule(ruleType, filename, {
                contentType: DECISION_CONTENT_TYPE,
                ...graph,
              });
              onSaved();
              respond?.({ accepted: true });
            } catch (e) {
              respond?.({ accepted: false, reason: (e as Error).message });
            }
          }}
          onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
        />
      );
    },
  });

  useCopilotAction({
    name: 'create_rule',
    description: 'Navigate to a blank editor for a new rule file.',
    parameters: [
      { name: 'rule_type', type: 'string', enum: ['onboarding', 'transaction-screening'], required: true },
      { name: 'filename', type: 'string', required: true },
    ],
    renderAndWaitForResponse: ({ args: a, status, respond }) => {
      const parsed = CreateRuleArgsSchema.safeParse(a);
      if (!parsed.success) {
        return (
          <PersistCard
            title="create_rule — invalid args"
            status={status as 'inProgress' | 'executing' | 'complete'}
            sideEffectLabel="Acknowledge"
            summary={<span>{parsed.error.message}</span>}
            onApply={() => respond?.({ accepted: false, reason: parsed.error.message })}
            onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
          />
        );
      }
      const v = parsed.data;
      return (
        <PersistCard
          title="create_rule"
          status={status as 'inProgress' | 'executing' | 'complete'}
          sideEffectLabel="Open blank editor"
          summary={
            <span>
              Open a blank editor for{' '}
              <code className="font-mono">
                {v.rule_type}/{v.filename}
              </code>
              .{dirty ? ' Unsaved changes in the current file will be discarded.' : ''}
            </span>
          }
          onApply={() => {
            navigate(`/rules/${v.rule_type}/${encodeURIComponent(v.filename)}?new=1`);
            respond?.({ accepted: true });
          }}
          onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
        />
      );
    },
  });

  useCopilotAction({
    name: 'delete_rule',
    description: 'Permanently remove a rule file from disk. Irreversible.',
    parameters: [
      { name: 'rule_type', type: 'string', enum: ['onboarding', 'transaction-screening'], required: true },
      { name: 'filename', type: 'string', required: true },
    ],
    renderAndWaitForResponse: ({ args: a, status, respond }) => {
      const parsed = DeleteRuleArgsSchema.safeParse(a);
      if (!parsed.success) {
        return (
          <DestructiveCard
            title="delete_rule — invalid args"
            status={status as 'inProgress' | 'executing' | 'complete'}
            filename=""
            warning={<span>{parsed.error.message}</span>}
            onApply={() => respond?.({ accepted: false, reason: parsed.error.message })}
            onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
          />
        );
      }
      const v = parsed.data;
      return (
        <DestructiveCard
          title="delete_rule"
          status={status as 'inProgress' | 'executing' | 'complete'}
          filename={v.filename}
          warning={
            <span>
              This will permanently delete{' '}
              <code className="font-mono">
                {v.rule_type}/{v.filename}
              </code>{' '}
              from disk.
            </span>
          }
          onApply={async () => {
            try {
              await deleteRule(v.rule_type as RuleType, v.filename);
              await refreshExistingRules();
              respond?.({ accepted: true });
            } catch (e) {
              respond?.({ accepted: false, reason: (e as Error).message });
            }
          }}
          onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
        />
      );
    },
  });

  useCopilotAction({
    name: 'open_rule',
    description: 'Navigate to a different rule.',
    parameters: [
      { name: 'rule_type', type: 'string', enum: ['onboarding', 'transaction-screening'], required: true },
      { name: 'filename', type: 'string', required: true },
    ],
    renderAndWaitForResponse: ({ args: a, status, respond }) => {
      const parsed = OpenRuleArgsSchema.safeParse(a);
      if (!parsed.success) {
        return (
          <PersistCard
            title="open_rule — invalid args"
            status={status as 'inProgress' | 'executing' | 'complete'}
            sideEffectLabel="Acknowledge"
            summary={<span>{parsed.error.message}</span>}
            onApply={() => respond?.({ accepted: false, reason: parsed.error.message })}
            onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
          />
        );
      }
      const v = parsed.data;
      return (
        <PersistCard
          title="open_rule"
          status={status as 'inProgress' | 'executing' | 'complete'}
          sideEffectLabel="Open"
          summary={
            <span>
              Open{' '}
              <code className="font-mono">
                {v.rule_type}/{v.filename}
              </code>
              .{dirty ? ' Unsaved changes in the current file will be discarded.' : ''}
            </span>
          }
          onApply={() => {
            navigate(`/rules/${v.rule_type}/${encodeURIComponent(v.filename)}`);
            respond?.({ accepted: true });
          }}
          onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
        />
      );
    },
  });
}
