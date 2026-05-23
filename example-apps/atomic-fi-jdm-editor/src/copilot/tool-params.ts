import { z } from 'zod';
import { NODE_TYPES } from './node-types';

// LLM-facing tool-parameter schemas for CopilotKit v2.
//
// v2 `useHumanInTheLoop` takes ONE Zod schema as `parameters` — it both
// builds the tool's JSON schema for the model and parses the model's
// tool-call args before `render` runs. These schemas are deliberately
// LOOSE: every field is optional and freeform values are `z.unknown()`,
// so a malformed arg can never hard-fail before `render`. The STRICT
// schemas in `node-types.ts` are still `safeParse`'d inside each render,
// against the live graph — that is where validation failures become
// self-correction feedback for the agent.
//
// See docs/copilot-architecture.md §5.

const positionDescription =
  'OMIT entirely unless the user asked for a specific placement. If passed, ' +
  'it must be { "x": <number>, "y": <number> } with both fields real numbers. ' +
  'The editor auto-positions nodes when this is omitted.';

const contentDescription =
  'JDM node content as a JSON object. OMIT for inputNode and outputNode ' +
  '(they have no content). REQUIRED for decisionTableNode / expressionNode / ' +
  'functionNode / switchNode — consult the JDM cheatsheet for the exact shape.';

export const AddNodeToolParams = z.object({
  type: z.enum(NODE_TYPES).describe('REQUIRED. The JDM node kind.').optional(),
  name: z.string().describe('REQUIRED. Human-readable node name.').optional(),
  content: z.unknown().describe(contentDescription),
  position: z.unknown().describe(positionDescription),
});

export const UpdateNodeToolParams = z.object({
  node_id: z
    .string()
    .describe(
      'REQUIRED. Either the real node id (from add_node) or the exact node ' +
        'name. Case-sensitive when matching by name.',
    )
    .optional(),
  patch: z
    .unknown()
    .describe('Canonical form: { name?, content?, position? }. Use this OR the ' + 'top-level shorthand, not both.'),
  name: z.string().describe('Shorthand: new node name.').optional(),
  content: z.unknown().describe('Shorthand: new node content (a JSON object).'),
  position: z.unknown().describe('Shorthand: new { x, y } position.'),
});

export const RemoveNodeToolParams = z.object({
  node_id: z.string().describe('REQUIRED. Either the real node id (from add_node) or the exact node name.').optional(),
});

export const AddEdgeToolParams = z.object({
  source_id: z
    .string()
    .describe('REQUIRED. Source node — id (preferred) or exact name. Case-sensitive when matching by name.')
    .optional(),
  target_id: z
    .string()
    .describe('REQUIRED. Target node — id (preferred) or exact name. Case-sensitive when matching by name.')
    .optional(),
  source_handle: z.string().describe('Optional source handle id.').optional(),
  target_handle: z.string().describe('Optional target handle id.').optional(),
});

export const RemoveEdgeToolParams = z.object({
  edge_id: z.string().describe('REQUIRED. The id of the edge to remove.').optional(),
});

// save_rule takes no parameters — it acts on the current open rule.
export const SaveRuleToolParams = z.object({});

export const RenameRuleToolParams = z.object({
  new_filename: z.string().describe('REQUIRED. New filename ending in .json, no path separators.').optional(),
});

const RuleFileToolParams = z.object({
  rule_type: z.enum(['onboarding', 'transaction-screening']).describe('REQUIRED. The rule type.').optional(),
  filename: z.string().describe('REQUIRED. Filename ending in .json, no path separators.').optional(),
});

export const CreateRuleToolParams = RuleFileToolParams;
export const DeleteRuleToolParams = RuleFileToolParams;
export const OpenRuleToolParams = RuleFileToolParams;

export const SimulateRuleToolParams = z.object({
  context_json: z
    .string()
    .describe(
      'REQUIRED. A JSON-ENCODED STRING of a non-empty context object that ' +
        'matches rule_engine_payload_schema. Example (note the OUTER quotes — ' +
        'this is a string, not an object): ' +
        '"{\\"account_holder\\": {\\"kyc_status\\": \\"approved\\"}}". ' +
        'Do NOT pass an object directly — small LLMs drop nested-object args. ' +
        'Always JSON.stringify the context yourself before passing.',
    )
    .optional(),
});
