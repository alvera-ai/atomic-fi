import { z } from 'zod';

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

export const AddNodeArgsSchema = z.object({
  type: z.enum(NODE_TYPES),
  name: z.string().min(1),
  content: z.record(z.string(), z.unknown()),
  position: PositionSchema.optional(),
});
export type AddNodeArgs = z.infer<typeof AddNodeArgsSchema>;

export const UpdateNodeArgsSchema = z.object({
  node_id: z.string().min(1),
  patch: z.object({
    name: z.string().optional(),
    content: z.record(z.string(), z.unknown()).optional(),
    position: PositionSchema.optional(),
  }),
});
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

export const SimulateRuleArgsSchema = z.object({
  context: z.unknown(),
});
