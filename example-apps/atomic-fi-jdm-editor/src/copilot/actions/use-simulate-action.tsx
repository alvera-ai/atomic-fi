import React from 'react';
import { useHumanInTheLoop } from '@copilotkit/react-core/v2';
import type { DecisionGraphType, Simulation } from '@gorules/jdm-editor';
import { runSimulation } from '../../helpers/simulator';
import type { RuleType } from '../../helpers/rules-api';
import { SimulateRuleArgsSchema } from '../node-types';
import { SimulateRuleToolParams } from '../tool-params';
import { PersistCard } from '../cards/persist-card';

type Args = {
  ruleType: RuleType;
  filename: string;
  dirty: boolean;
  graph: DecisionGraphType;
  setLastSimulation: (s: Simulation) => void;
};

// CopilotKit v2 simulate tool. Registered once (`deps: []`); the render reads
// the session-drifting values (ruleType, filename, dirty, graph) through refs
// so a delayed Apply evaluates against current editor state.
export function useSimulateAction(args: Args): void {
  const { ruleType, filename, dirty, graph, setLastSimulation } = args;

  const ruleTypeRef = React.useRef(ruleType);
  const filenameRef = React.useRef(filename);
  const dirtyRef = React.useRef(dirty);
  const graphRef = React.useRef(graph);
  React.useEffect(() => {
    ruleTypeRef.current = ruleType;
  }, [ruleType]);
  React.useEffect(() => {
    filenameRef.current = filename;
  }, [filename]);
  React.useEffect(() => {
    dirtyRef.current = dirty;
  }, [dirty]);
  React.useEffect(() => {
    graphRef.current = graph;
  }, [graph]);

  useHumanInTheLoop(
    {
      name: 'simulate_rule',
      description:
        'Run the last saved version of the current rule against a JSON context. ' +
        'Pass the context as a JSON-ENCODED STRING in the `context_json` argument — small models drop nested-object args. ' +
        'The trace lands in last_simulation on the next turn.',
      parameters: SimulateRuleToolParams,
      // toolCallId cast — see use-graph-actions.tsx for the explanation.
      render: (props) => {
        const { args: a, status, respond } = props;
        const { toolCallId } = props as never as { toolCallId: string };
        // Surface the raw tool-call args so we can see exactly what the LLM
        // sent. Saved us at least once already (the "{trace:true}" mystery).

        console.log('[copilot] simulate_rule raw args:', a);
        const parsed = SimulateRuleArgsSchema.safeParse(a);
        if (!parsed.success) {
          // Surface the issue plainly so the user knows what to ask the agent
          // for, and feed the reason back to the LLM so it self-corrects.
          const reason = parsed.error.issues
            .map((iss) => `${iss.path.join('.') || '<root>'}: ${iss.message}`)
            .join('; ');
          return (
            <PersistCard
              toolCallId={toolCallId}
              title="simulate_rule — missing context"
              status={status}
              sideEffectLabel="Acknowledge"
              summary={
                <span>
                  Cannot simulate: <code className="font-mono">{reason}</code>. The agent must pass a concrete{' '}
                  <code className="font-mono">context</code> object (e.g.{' '}
                  <code className="font-mono">{'{ "account_holder": { "kyc_status": "approved" } }'}</code>) — not an
                  empty body.
                </span>
              }
              onApply={() => respond?.({ accepted: false, reason })}
              onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
            />
          );
        }
        return (
          <PersistCard
            toolCallId={toolCallId}
            title="simulate_rule"
            status={status}
            sideEffectLabel="Run simulation"
            summary={
              <span>
                {dirtyRef.current
                  ? 'Evaluates the LAST SAVED version. Unsaved changes are ignored — save first if you want them tested.'
                  : `Evaluate ${filenameRef.current} against the provided context.`}
              </span>
            }
            diff={JSON.stringify(parsed.data.context, null, 2)}
            onApply={async () => {
              try {
                const sim = await runSimulation({
                  ruleType: ruleTypeRef.current,
                  name: filenameRef.current,
                  input: { graph: graphRef.current, context: parsed.data.context },
                });
                setLastSimulation(sim);
                await respond?.({
                  accepted: true,
                  result: sim.result?.result ?? null,
                  trace: sim.result?.trace ?? {},
                  error: sim.error ?? null,
                });
              } catch (e) {
                await respond?.({ accepted: false, reason: (e as Error).message });
              }
            }}
            onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
          />
        );
      },
    },
    [],
  );
}
