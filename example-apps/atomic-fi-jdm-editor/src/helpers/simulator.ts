/**
 * Simulator integration: routes the editor's <GraphSimulator onRun={…}> to the
 * atomic-fi project's existing ZenRule agent (see local-dependencies.yaml).
 *
 * The agent only evaluates *saved* decisions — there is no inline-content
 * simulate endpoint. So this helper assumes the file has already been written
 * to priv/zenrule/atomic-fi/<key>.json on disk; the agent's hot-reload picks
 * up the change within its poll interval (~1s by default).
 *
 * TODO(draft-state): when we add an inline /api/simulate handler (either to
 * the vendored agent in external-deps/zenrule/ or via a Phoenix proxy), the
 * `content` field can be sent in the request body and the Save-then-Simulate
 * constraint goes away. Tracked in:
 *   docs/superpowers/specs/2026-05-13-jdm-editor-scaffold-design.md — Followups (Phase 3a/b)
 */

import axios from 'axios';
import type { DecisionGraphType, Simulation } from '@gorules/jdm-editor';

const PROJECT = 'atomic-fi';

export type SimulateRunInput = {
  graph: DecisionGraphType;
  context: unknown;
};

/**
 * Evaluates the *saved* decision identified by `key` against `context` via the
 * ZenRule agent. Returns a value shaped for `setGraphTrace(...)`.
 *
 * Precondition: `key` must be a non-empty, validated filename (see
 * `fileNameToKey`). Behaviour with an empty key is undefined.
 */
export async function runSimulation(args: { key: string; input: SimulateRunInput }): Promise<Simulation> {
  const { key, input } = args;

  try {
    const { data } = await axios.post(`/api/projects/${PROJECT}/evaluate/${encodeURIComponent(key)}`, {
      context: input.context,
      trace: true,
    });

    // Agent response shape: { details: {...}, result, trace, performance, ... }.
    // We drop `details` and rebuild into the editor's Simulation shape.
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

/**
 * Derives the agent's decision `key` from the current editor `fileName`.
 * Returns `null` if the name is invalid (caller should surface an error).
 */
export function fileNameToKey(fileName: string | undefined): string | null {
  if (!fileName) return null;
  const trimmed = fileName.trim();
  if (!trimmed.endsWith('.json')) return null;
  if (trimmed.includes('/') || trimmed.includes('\\')) return null;
  // Reject bare ".json" (no stem) — the agent won't have a hidden file matching.
  if (trimmed.length <= '.json'.length) return null;
  return trimmed;
}
