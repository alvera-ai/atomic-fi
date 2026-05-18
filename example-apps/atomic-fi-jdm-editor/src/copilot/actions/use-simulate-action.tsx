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
      'Run the last saved version of the current rule against a JSON context. The trace lands in last_simulation on the next turn.',
    parameters: [
      {
        name: 'context',
        type: 'object',
        required: true,
        description:
          'JSON context matching rule_engine_payload_schema. Use only fields present in the schema readable.',
      },
    ],
    renderAndWaitForResponse: ({ args: a, status, respond }) => {
      const parsed = SimulateRuleArgsSchema.safeParse(a);
      if (!parsed.success) {
        return (
          <PersistCard
            title="simulate_rule — invalid args"
            status={status as 'inProgress' | 'executing' | 'complete'}
            sideEffectLabel="Acknowledge"
            summary={<span>{parsed.error.message}</span>}
            onApply={() => respond?.({ accepted: false, reason: parsed.error.message })}
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
