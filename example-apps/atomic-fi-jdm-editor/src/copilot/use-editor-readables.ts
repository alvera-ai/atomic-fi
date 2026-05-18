import { useCopilotReadable } from '@copilotkit/react-core';
import type { DecisionGraphType, Simulation } from '@gorules/jdm-editor';
import { RULE_ENGINE_PAYLOAD_SCHEMA } from './payload-schema';
import { JDM_CHEATSHEET } from './jdm-cheatsheet';
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

export function useEditorReadables(args: EditorReadablesArgs): void {
  useCopilotReadable({
    description: 'Metadata about the rule the user is currently editing.',
    value: JSON.stringify({
      rule_type: args.ruleType,
      filename: args.filename,
      is_new: args.isNew,
      dirty: args.dirty,
      saved_revision: args.savedRevision,
    }),
  });

  useCopilotReadable({
    description: 'The full JDM decision graph the user is currently editing — { nodes, edges }.',
    value: JSON.stringify(args.graph),
  });

  useCopilotReadable({
    description: 'Valid rule_type values.',
    value: JSON.stringify(RULE_TYPES),
  });

  useCopilotReadable({
    description:
      'Schema of the JSON context against which rules are evaluated. Use only these field paths in inputs[].field.',
    value: JSON.stringify(RULE_ENGINE_PAYLOAD_SCHEMA),
  });

  useCopilotReadable({
    description:
      'JDM authoring cheatsheet. ALWAYS consult this before producing decisionTableNode/expressionNode/functionNode content. Covers the exact shape of decision-table content (hitPolicy/inputs/outputs/rules), ZEN cell expression syntax (string literals need INNER quotes), and includes a canonical 3-node graph example.',
    value: JDM_CHEATSHEET,
  });

  useCopilotReadable({
    description: 'Result of the most recent simulate_rule call — { context, trace, error } or null if none yet.',
    value: JSON.stringify(args.lastSimulation),
  });

  useCopilotReadable({
    description: 'Names of rule files already on disk, grouped by rule_type. Use to avoid name collisions.',
    value: JSON.stringify(args.existingRules),
  });
}
