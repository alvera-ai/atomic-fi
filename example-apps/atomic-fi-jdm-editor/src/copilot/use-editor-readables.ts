import { useAgentContext } from '@copilotkit/react-core/v2';
import type { DecisionGraphType, Simulation } from '@gorules/jdm-editor';
import { RULE_ENGINE_PAYLOAD_SCHEMA } from './payload-schema';
import { JDM_CHEATSHEET } from './jdm-cheatsheet';
// Vite ?raw import — the markdown is inlined as a string at build time.
// This is the JDM-domain authoring prompt the LLM needs as a leading
// system instruction, mirroring the SYSTEM_PROMPT injected server-side by
// the v1 worktree's runtime middleware. Our v2 runtime is generic, so the
// domain prompt lives with the editor app instead of the sidecar.
import SYSTEM_PROMPT from './system-prompt.md?raw';
import { RULE_TYPES, type RuleType } from '../helpers/rules-api';

type EditorReadablesArgs = {
  ruleType: RuleType;
  filename: string;
  isNew: boolean;
  dirty: boolean;
  savedRevision: number;
  graph: DecisionGraphType;
  lastSimulation: Simulation | null;
  existingRules: Record<RuleType, string[] | undefined>;
};

// Publishes editor state to the agent as CopilotKit v2 agent context.
// v2's `useAgentContext` is the 1:1 successor to v1's `useCopilotReadable`
// — same { description, value } shape. See docs/copilot-architecture.md §7.
export function useEditorReadables(args: EditorReadablesArgs): void {
  // FIRST readable — the authoring prompt. Goes at the top of the projected
  // system message so the LLM reads its role + tool-use discipline before
  // any application state. Without this the model treats "modify the rule"
  // requests as conversation ("I will update the rule") instead of firing
  // update_node — the regression the user spotted vs the v1 worktree.
  useAgentContext({
    description:
      'JDM-rule authoring instructions — your role, the tools you have, and the discipline you must follow. Read this every turn before doing anything else.',
    value: SYSTEM_PROMPT,
  });

  useAgentContext({
    description: 'Metadata about the rule the user is currently editing.',
    value: JSON.stringify({
      rule_type: args.ruleType,
      filename: args.filename,
      is_new: args.isNew,
      dirty: args.dirty,
      saved_revision: args.savedRevision,
    }),
  });

  useAgentContext({
    description: 'The full JDM decision graph the user is currently editing — { nodes, edges }.',
    value: JSON.stringify(args.graph),
  });

  useAgentContext({
    description: 'Valid rule_type values.',
    value: JSON.stringify(RULE_TYPES),
  });

  useAgentContext({
    description:
      'Schema of the JSON context against which rules are evaluated. Use only these field paths in inputs[].field.',
    value: JSON.stringify(RULE_ENGINE_PAYLOAD_SCHEMA),
  });

  useAgentContext({
    description:
      'JDM authoring cheatsheet. ALWAYS consult this before producing decisionTableNode/expressionNode/functionNode content. Covers the exact shape of decision-table content (hitPolicy/inputs/outputs/rules), ZEN cell expression syntax (string literals need INNER quotes), and includes a canonical 3-node graph example.',
    value: JDM_CHEATSHEET,
  });

  useAgentContext({
    description: 'Result of the most recent simulate_rule call — { context, trace, error } or null if none yet.',
    value: JSON.stringify(args.lastSimulation),
  });

  useAgentContext({
    description: 'Names of rule files already on disk, grouped by rule_type. Use to avoid name collisions.',
    value: JSON.stringify(args.existingRules),
  });
}
