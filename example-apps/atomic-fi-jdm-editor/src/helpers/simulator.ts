/**
 * Simulator integration: routes the editor's <GraphSimulator onRun={…}> to the
 * ZenRule agent (see local-dependencies.yaml).
 *
 * ZenRule hosts one project per rule_type (`onboarding`, `transaction-screening`).
 * Files live under priv/zenrule/<rule_type>/<name>.json. The agent only
 * evaluates *saved* decisions; the agent hot-reloads within its poll interval
 * (~1s), so save first, then simulate.
 */

import type { DecisionGraphType, Simulation } from '@gorules/jdm-editor';
import axios from 'axios';
import { zenruleClient } from './clients';
import type { RuleType } from './rules-api';

export type SimulateRunInput = {
  graph: DecisionGraphType;
  context: unknown;
};

export async function runSimulation(args: {
  ruleType: RuleType;
  name: string;
  input: SimulateRunInput;
}): Promise<Simulation> {
  const { ruleType, name, input } = args;

  try {
    const { data } = await zenruleClient.post(
      `/api/projects/${ruleType}/evaluate/${encodeURIComponent(name)}`,
      {
        context: input.context,
        trace: true,
      },
    );

    const { result, trace, performance } = data ?? {};
    return {
      result: {
        performance: performance ?? '',
        result,
        snapshot: input.graph,
        trace: trace ?? {},
      },
    };
  } catch (e) {
    if (axios.isAxiosError(e)) {
      const errData = e.response?.data;
      const composedMessage =
        errData && typeof errData.type === 'string' && typeof errData.source === 'string'
          ? `${errData.type}: ${errData.source}`
          : (errData?.source ?? errData?.message ?? e.message);
      return {
        result: {
          performance: '',
          result: null,
          snapshot: input.graph,
          trace: e.response?.data?.trace ?? {},
        },
        error: {
          message: composedMessage,
          data: { nodeId: errData?.nodeId },
        },
      };
    }
    throw e;
  }
}
