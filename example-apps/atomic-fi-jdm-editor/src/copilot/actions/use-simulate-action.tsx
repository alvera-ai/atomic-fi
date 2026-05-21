import React from 'react';
import { useCopilotAction } from '@copilotkit/react-core';
import type { DecisionGraphType, Simulation } from '@gorules/jdm-editor';
import { runSimulation } from '../../helpers/simulator';
import type { RuleType } from '../../helpers/rules-api';
import { SimulateRuleArgsSchema } from '../node-types';
import { PersistCard } from '../cards/persist-card';

type Args = {
  ruleType: RuleType;
  filename: string;
  dirty: boolean;
  graph: DecisionGraphType;
  setLastSimulation: (s: Simulation) => void;
};

export function useSimulateAction(args: Args): void {
  const { ruleType, filename, dirty, graph, setLastSimulation } = args;

  useCopilotAction({
    name: 'simulate_rule',
    description:
      'Run the last saved version of the current rule against a JSON context. ' +
      "Pass the context as a JSON-ENCODED STRING in the `context_json` argument — small models drop nested-object args. " +
      'The trace lands in last_simulation on the next turn.',
    parameters: [
      {
        name: 'context_json',
        type: 'string',
        required: true,
        description:
          'REQUIRED. A JSON-ENCODED STRING describing a non-empty context object that matches rule_engine_payload_schema. ' +
          'Example value (note the OUTER quotes — this is a string, not an object): ' +
          '"{\\"account_holder\\": {\\"kyc_status\\": \\"approved\\"}}". ' +
          "Do NOT pass an object directly — small LLMs drop nested-object args. Always JSON.stringify the context yourself before passing.",
      },
    ],
    renderAndWaitForResponse: ({ args: a, status, respond }) => {
      // Surface the raw tool-call args so we can see exactly what the LLM
      // sent. Saved us at least once already (the "{trace:true}" mystery).
      // eslint-disable-next-line no-console
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
            title="simulate_rule — missing context"
            status={status as 'inProgress' | 'executing' | 'complete'}
            sideEffectLabel="Acknowledge"
            summary={
              <span>
                Cannot simulate: <code className="font-mono">{reason}</code>. The agent must pass a
                concrete <code className="font-mono">context</code> object (e.g.{' '}
                <code className="font-mono">{'{ "account_holder": { "kyc_status": "approved" } }'}</code>
                ) — not an empty body.
              </span>
            }
            onApply={() => respond?.({ accepted: false, reason })}
            onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
          />
        );
      }
      return (
        <PersistCard
          title="simulate_rule"
          status={status as 'inProgress' | 'executing' | 'complete'}
          sideEffectLabel="Run simulation"
          summary={
            <span>
              {dirty
                ? 'Evaluates the LAST SAVED version. Unsaved changes are ignored — save first if you want them tested.'
                : `Evaluate ${filename} against the provided context.`}
            </span>
          }
          diff={JSON.stringify(parsed.data.context, null, 2)}
          onApply={async () => {
            try {
              const sim = await runSimulation({
                ruleType,
                name: filename,
                input: { graph, context: parsed.data.context },
              });
              setLastSimulation(sim);
              respond?.({
                accepted: true,
                result: sim.result?.result ?? null,
                trace: sim.result?.trace ?? {},
                error: sim.error ?? null,
              });
            } catch (e) {
              respond?.({ accepted: false, reason: (e as Error).message });
            }
          }}
          onReject={() => respond?.({ accepted: false, reason: 'Rejected by user' })}
        />
      );
    },
  });
}
