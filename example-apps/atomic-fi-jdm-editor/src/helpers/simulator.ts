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
      const status = e.response?.status ?? 0;
      // Build the richest possible human message: prefer ZenRule's
      // {type, source} pair, then any of source/message/detail, then HTTP
      // status as a last resort. Most ZenRule compile errors come as 422
      // with `{ type, source, nodeId }`; surface all of it so the agent
      // can self-correct instead of just seeing "422".
      const parts: string[] = [];
      if (typeof errData?.type === 'string') parts.push(errData.type);
      if (typeof errData?.source === 'string') parts.push(errData.source);
      else if (typeof errData?.message === 'string') parts.push(errData.message);
      else if (typeof errData?.detail === 'string') parts.push(errData.detail);
      const composedMessage =
        parts.length > 0
          ? `[HTTP ${status}] ${parts.join(': ')}`
          : `[HTTP ${status}] ${e.message}`;

      // Log the full response body to console so a developer watching the
      // browser devtools can see exactly what ZenRule said. The agent-side
      // `error.message` carries the human summary above.
      // eslint-disable-next-line no-console
      console.error('[simulator] ZenRule rejected the request', {
        status,
        url: e.config?.url,
        responseData: errData,
      });

      // Encode the full ZenRule payload inside `message` as a fenced JSON
      // block. The Simulation type's `data` only allows `{ nodeId? }`, so
      // we route the rich details (status, raw body) into the message text.
      // The agent reads `last_simulation.error.message` to extract them.
      const richMessage =
        `${composedMessage}\n\nZenRule response:\n` +
        '```json\n' +
        JSON.stringify({ status, body: errData }, null, 2) +
        '\n```';
      return {
        result: {
          performance: '',
          result: null,
          snapshot: input.graph,
          trace: e.response?.data?.trace ?? {},
        },
        error: {
          message: richMessage,
          data: { nodeId: errData?.nodeId },
        },
      };
    }
    throw e;
  }
}
