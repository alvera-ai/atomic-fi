import { z } from 'zod';

// Some LLMs (notably GPT-4o-mini) emit nested-object tool args as JSON-encoded
// strings instead of structured objects. JSON-parse strings before validation
// so the agent can pass either shape.
const parseIfJsonString = (v: unknown): unknown => {
  if (typeof v !== 'string') return v;
  try {
    return JSON.parse(v);
  } catch {
    return v;
  }
};

export const NODE_TYPES = [
  'inputNode',
  'outputNode',
  'decisionTableNode',
  'expressionNode',
  'functionNode',
  'switchNode',
  'customNode',
  'decisionNode',
] as const;
export type NodeType = (typeof NODE_TYPES)[number];

export const PositionSchema = z.object({
  x: z.number(),
  y: z.number(),
});

// Coerce malformed positions to "no position" (undefined). LLMs sometimes
// emit `position: {}` or `position: { x: null }` when they don't mean to
// override placement — treating those as "use auto-positioning" is more
// forgiving than rejecting the whole add_node call. A real {x: number,
// y: number} passes through unchanged.
const TolerantPositionPreprocess = (v: unknown): unknown => {
  const parsed = parseIfJsonString(v);
  if (parsed === null || parsed === undefined) return undefined;
  if (typeof parsed !== 'object') return undefined;
  const obj = parsed as Record<string, unknown>;
  if (typeof obj.x !== 'number' || typeof obj.y !== 'number') return undefined;
  return parsed;
};

export const AddNodeArgsSchema = z.object({
  type: z.enum(NODE_TYPES),
  name: z.string().min(1),
  // inputNode and outputNode legitimately have no `content` per JDM
  // (zenrule-author skill convention). Decision/expression/function/switch
  // nodes do need content but we let the agent omit it without failing — a
  // missing content for those node types will surface as a ZenRule compile
  // error at simulate time, which is the right place to catch it.
  content: z.preprocess(parseIfJsonString, z.record(z.string(), z.unknown()).optional()),
  position: z.preprocess(TolerantPositionPreprocess, PositionSchema.optional()),
});
export type AddNodeArgs = z.infer<typeof AddNodeArgsSchema>;

// Accept both the canonical `{ node_id, patch: { name?, content?, position? } }`
// shape AND the shorthand `{ node_id, name?/content?/position? }` that LLMs
// often emit when the nested envelope is awkward to express. We collapse both
// to the canonical patch shape in the schema's output.
const UpdateNodePatchSchema = z.object({
  name: z.string().optional(),
  content: z.preprocess(parseIfJsonString, z.record(z.string(), z.unknown()).optional()),
  position: z.preprocess(TolerantPositionPreprocess, PositionSchema.optional()),
});

export const UpdateNodeArgsSchema = z
  .object({
    node_id: z.string().min(1),
    patch: z.preprocess(parseIfJsonString, UpdateNodePatchSchema.optional()),
    // Top-level shorthand fields — used only if `patch` is absent.
    name: z.string().optional(),
    content: z.preprocess(parseIfJsonString, z.record(z.string(), z.unknown()).optional()),
    position: z.preprocess(TolerantPositionPreprocess, PositionSchema.optional()),
  })
  .transform((obj) => {
    const patch =
      obj.patch ??
      ({
        ...(obj.name !== undefined ? { name: obj.name } : {}),
        ...(obj.content !== undefined ? { content: obj.content } : {}),
        ...(obj.position !== undefined ? { position: obj.position } : {}),
      } satisfies z.infer<typeof UpdateNodePatchSchema>);
    return { node_id: obj.node_id, patch };
  })
  .refine(
    (v) => v.patch && (v.patch.name !== undefined || v.patch.content !== undefined || v.patch.position !== undefined),
    {
      message: 'update_node requires at least one of: patch.name, patch.content, or patch.position (or the top-level shorthand)',
    },
  );
export type UpdateNodeArgs = z.infer<typeof UpdateNodeArgsSchema>;

export const RemoveNodeArgsSchema = z.object({
  node_id: z.string().min(1),
});

export const AddEdgeArgsSchema = z.object({
  source_id: z.string().min(1),
  target_id: z.string().min(1),
  source_handle: z.string().optional(),
  target_handle: z.string().optional(),
});

export const RemoveEdgeArgsSchema = z.object({
  edge_id: z.string().min(1),
});

export const CreateRuleArgsSchema = z.object({
  rule_type: z.enum(['onboarding', 'transaction-screening']),
  filename: z
    .string()
    .min(1)
    .regex(/^[A-Za-z0-9_-]+\.json$/, 'Filename must end in .json and contain no path separators.'),
});

export const DeleteRuleArgsSchema = CreateRuleArgsSchema;
export const OpenRuleArgsSchema = CreateRuleArgsSchema;

export const RenameRuleArgsSchema = z.object({
  new_filename: z
    .string()
    .min(1)
    .regex(/^[A-Za-z0-9_-]+\.json$/, 'Filename must end in .json and contain no path separators.'),
});

// `simulate_rule` accepts the context either as a structured object (`context`)
// or — more reliably for small/mid LLMs that struggle with nested-object tool
// args — as a JSON-encoded string (`context_json`). One of the two must be a
// non-empty object after parsing.
//
// We tried `context: object (required)` originally; gpt-4o-mini repeatedly
// described the JSON in its chat reply but emitted the actual tool call with
// arguments = "{}". String params don't have this problem.
const isNonEmptyObject = (v: unknown): v is Record<string, unknown> =>
  v !== null && typeof v === 'object' && !Array.isArray(v) && Object.keys(v as object).length > 0;

export const SimulateRuleArgsSchema = z
  .object({
    context: z.preprocess(parseIfJsonString, z.unknown()).optional(),
    context_json: z.string().optional(),
  })
  .transform((v, ctx) => {
    let resolved: Record<string, unknown> | undefined;
    if (isNonEmptyObject(v.context)) {
      resolved = v.context;
    } else if (typeof v.context_json === 'string' && v.context_json.trim().length > 0) {
      try {
        const parsed = JSON.parse(v.context_json);
        if (isNonEmptyObject(parsed)) {
          resolved = parsed;
        } else {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: `context_json parsed but produced ${Array.isArray(parsed) ? 'an array' : typeof parsed} — expected a non-empty JSON object.`,
            path: ['context_json'],
          });
        }
      } catch (err) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: `context_json is not valid JSON: ${(err as Error).message}`,
          path: ['context_json'],
        });
      }
    } else {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message:
          'context_json (a JSON-encoded string of a non-empty object) is required. Example: \'{"account_holder": {"kyc_status": "approved"}}\'',
        path: ['context_json'],
      });
    }
    return { context: resolved as Record<string, unknown> };
  });
