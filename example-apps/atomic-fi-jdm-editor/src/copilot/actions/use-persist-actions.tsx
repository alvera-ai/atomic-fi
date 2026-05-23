import React from 'react';
import { useHumanInTheLoop } from '@copilotkit/react-core/v2';
import { useNavigate } from 'react-router-dom';
import type { DecisionGraphType } from '@gorules/jdm-editor';
import { DirectedGraph } from 'graphology';
import { hasCycle } from 'graphology-dag';
import { CreateRuleArgsSchema, DeleteRuleArgsSchema, OpenRuleArgsSchema, RenameRuleArgsSchema } from '../node-types';
import {
  CreateRuleToolParams,
  DeleteRuleToolParams,
  OpenRuleToolParams,
  RenameRuleToolParams,
  SaveRuleToolParams,
} from '../tool-params';
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

// CopilotKit v2 persistence tools. Each tool is registered once (`deps: []`);
// the render closures read the values that drift over a session — dirty,
// graph, filename, ruleType — through refs kept current below, so a long
// pause between the agent emitting a tool call and the user pressing Apply
// never persists stale state. See docs/copilot-architecture.md §5.
export function usePersistActions(args: Args): void {
  const navigate = useNavigate();
  const { ruleType, filename, dirty, graph, onSaved, refreshExistingRules } = args;

  const dirtyRef = React.useRef(dirty);
  const graphRef = React.useRef(graph);
  const filenameRef = React.useRef(filename);
  const ruleTypeRef = React.useRef(ruleType);
  React.useEffect(() => {
    dirtyRef.current = dirty;
  }, [dirty]);
  React.useEffect(() => {
    graphRef.current = graph;
  }, [graph]);
  React.useEffect(() => {
    filenameRef.current = filename;
  }, [filename]);
  React.useEffect(() => {
    ruleTypeRef.current = ruleType;
  }, [ruleType]);

  useHumanInTheLoop(
    {
      name: 'save_rule',
      description:
        'Persist the current open graph to disk. Uses the current rule_type and filename from current_rule_meta.',
      parameters: SaveRuleToolParams,
      render: ({ status, respond }) => {
        const currentGraph = graphRef.current;
        const cyclic = isCyclic(currentGraph);
        return (
          <PersistCard
            title="save_rule"
            status={status}
            sideEffectLabel="Save"
            summary={
              <span>
                {cyclic
                  ? 'Graph has a cycle — refuse to save.'
                  : dirtyRef.current
                    ? `Will write ${filenameRef.current} (${(currentGraph.nodes ?? []).length} nodes, ${(currentGraph.edges ?? []).length} edges) to disk.`
                    : 'No unsaved changes; save will be a no-op.'}
              </span>
            }
            onApply={async () => {
              // Re-read everything from refs at click time so a long pause
              // between the agent emitting save_rule and the user pressing
              // Apply doesn't save a stale graph.
              const liveGraph = graphRef.current;
              const liveFilename = filenameRef.current;
              const liveRuleType = ruleTypeRef.current;
              if (isCyclic(liveGraph)) {
                respond?.({ accepted: false, reason: 'Graph has a cycle; refuse to save.' });
                return;
              }
              try {
                await saveRule(liveRuleType, liveFilename, {
                  contentType: DECISION_CONTENT_TYPE,
                  ...liveGraph,
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
    },
    [],
  );

  useHumanInTheLoop(
    {
      name: 'rename_rule',
      description:
        'Rename the currently open rule file. Saves the current graph under the new filename, deletes the old file, and navigates to the new editor URL. Same rule_type — to move across rule types, use create_rule and delete_rule explicitly.',
      parameters: RenameRuleToolParams,
      render: ({ args: a, status, respond }) => {
        const parsed = RenameRuleArgsSchema.safeParse(a);
        if (!parsed.success) {
          return (
            <PersistCard
              title="rename_rule — invalid args"
              status={status}
              sideEffectLabel="Acknowledge"
              summary={<span>{parsed.error.message}</span>}
              onApply={() => respond?.({ accepted: false, reason: parsed.error.message })}
              onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
            />
          );
        }
        const v = parsed.data;
        const sameName = v.new_filename === filenameRef.current;
        const cyclic = isCyclic(graphRef.current);
        return (
          <PersistCard
            title="rename_rule"
            status={status}
            sideEffectLabel="Rename"
            summary={
              <span>
                {sameName
                  ? `New filename matches the current one (${filenameRef.current}) — no-op.`
                  : cyclic
                    ? 'Graph has a cycle — refuse to rename.'
                    : `Will save under ${v.new_filename}, delete ${filenameRef.current}, then open the new file.`}
              </span>
            }
            onApply={async () => {
              const liveFilename = filenameRef.current;
              const liveRuleType = ruleTypeRef.current;
              const liveGraph = graphRef.current;
              if (v.new_filename === liveFilename) {
                respond?.({ accepted: false, reason: 'New filename equals the current one.' });
                return;
              }
              if (isCyclic(liveGraph)) {
                respond?.({ accepted: false, reason: 'Graph has a cycle; refuse to rename.' });
                return;
              }
              if (!liveFilename) {
                respond?.({ accepted: false, reason: 'No current filename — use save_rule instead.' });
                return;
              }
              try {
                // Save under the new name first; only delete the old file once
                // the save is confirmed so we don't lose data on transient failures.
                await saveRule(liveRuleType, v.new_filename, { contentType: DECISION_CONTENT_TYPE, ...liveGraph });
                try {
                  await deleteRule(liveRuleType, liveFilename);
                } catch (deleteErr) {
                  // Rename half-succeeded: the new file exists, the old still does.
                  // Surface the partial outcome to the agent rather than masking it.
                  respond?.({
                    accepted: false,
                    reason: `Saved under ${v.new_filename} but failed to delete ${liveFilename}: ${(deleteErr as Error).message}`,
                  });
                  return;
                }
                onSaved();
                await refreshExistingRules();
                navigate(`/rules/${liveRuleType}/${encodeURIComponent(v.new_filename)}`);
                respond?.({ accepted: true });
              } catch (e) {
                respond?.({ accepted: false, reason: (e as Error).message });
              }
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
      name: 'create_rule',
      description: 'Navigate to a blank editor for a new rule file.',
      parameters: CreateRuleToolParams,
      render: ({ args: a, status, respond }) => {
        const parsed = CreateRuleArgsSchema.safeParse(a);
        if (!parsed.success) {
          return (
            <PersistCard
              title="create_rule — invalid args"
              status={status}
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
            status={status}
            sideEffectLabel="Open blank editor"
            summary={
              <span>
                Open a blank editor for{' '}
                <code className="font-mono">
                  {v.rule_type}/{v.filename}
                </code>
                .{dirtyRef.current ? ' Unsaved changes in the current file will be discarded.' : ''}
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
    },
    [],
  );

  useHumanInTheLoop(
    {
      name: 'delete_rule',
      description: 'Permanently remove a rule file from disk. Irreversible.',
      parameters: DeleteRuleToolParams,
      render: ({ args: a, status, respond }) => {
        const parsed = DeleteRuleArgsSchema.safeParse(a);
        if (!parsed.success) {
          return (
            <DestructiveCard
              title="delete_rule — invalid args"
              status={status}
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
            status={status}
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
    },
    [],
  );

  useHumanInTheLoop(
    {
      name: 'open_rule',
      description: 'Navigate to a different rule.',
      parameters: OpenRuleToolParams,
      render: ({ args: a, status, respond }) => {
        const parsed = OpenRuleArgsSchema.safeParse(a);
        if (!parsed.success) {
          return (
            <PersistCard
              title="open_rule — invalid args"
              status={status}
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
            status={status}
            sideEffectLabel="Open"
            summary={
              <span>
                Open{' '}
                <code className="font-mono">
                  {v.rule_type}/{v.filename}
                </code>
                .{dirtyRef.current ? ' Unsaved changes in the current file will be discarded.' : ''}
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
    },
    [],
  );
}
