// Lightweight JDM (GoRules JSON Decision Model) evaluator.
// Supports a useful subset: inputNode → decisionTableNode(s) → outputNode.
// Cell expression grammar (per cell):
//   ""                       → wildcard match
//   "<literal>"              → equals literal
//   '== "x"' / "!= 1"        → comparison
//   ">", ">=", "<", "<="     → numeric compare
//   "in [\"a\",\"b\"]"       → membership
//   "not in [...]"           → negation
//   "contains \"x\""         → substring
//   "between [1, 10]"        → inclusive range
//   "<expr> and <expr>"      → AND of two cell expressions
//
// Output cells are JSON literals. Hit policies: "first" returns first matching row,
// "collect" returns all matching rows merged with `_matchedRows` array.

import type {
  JdmDecisionTableContent, JdmGraph, JdmInputField, JdmRule,
  MatchedCondition, Rule, RuleConditionGroup, RuleHit, RuleNode,
} from "@/api/types";

// ─── Resolve dotted path
const get = (obj: Record<string, unknown>, path: string): unknown => {
  if (path in obj) return obj[path];
  return path.split(".").reduce<unknown>(
    (acc, k) => (acc && typeof acc === "object" ? (acc as Record<string, unknown>)[k] : undefined),
    obj,
  );
};

// ─── Cell expression evaluator
const parseLiteral = (s: string): unknown => {
  const t = s.trim();
  if (!t) return undefined;
  if (t === "true") return true;
  if (t === "false") return false;
  if (t === "null") return null;
  if (/^-?\d+(\.\d+)?$/.test(t)) return Number(t);
  if ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'"))) {
    return t.slice(1, -1);
  }
  if (t.startsWith("[") && t.endsWith("]")) {
    try { return JSON.parse(t.replace(/'/g, '"')); } catch { return t; }
  }
  return t;
};

const evalAtom = (actual: unknown, expr: string): boolean => {
  const e = expr.trim();
  if (!e) return true; // wildcard
  // operators with rhs
  const ops: Array<[string, (a: unknown, v: unknown) => boolean]> = [
    [">=", (a, v) => typeof a === "number" && typeof v === "number" && a >= v],
    ["<=", (a, v) => typeof a === "number" && typeof v === "number" && a <= v],
    ["==", (a, v) => a === v],
    ["!=", (a, v) => a !== v],
    [">",  (a, v) => typeof a === "number" && typeof v === "number" && a > v],
    ["<",  (a, v) => typeof a === "number" && typeof v === "number" && a < v],
  ];
  for (const [sym, fn] of ops) {
    if (e.startsWith(sym)) return fn(actual, parseLiteral(e.slice(sym.length)));
  }
  if (e.startsWith("not in")) {
    const v = parseLiteral(e.slice(6));
    return Array.isArray(v) && !v.includes(actual as never);
  }
  if (e.startsWith("in ")) {
    const v = parseLiteral(e.slice(3));
    return Array.isArray(v) && v.includes(actual as never);
  }
  if (e.startsWith("contains")) {
    const v = parseLiteral(e.slice(8));
    return typeof actual === "string" && typeof v === "string" && actual.toLowerCase().includes(v.toLowerCase());
  }
  if (e.startsWith("between")) {
    const v = parseLiteral(e.slice(7));
    return Array.isArray(v) && v.length === 2 && typeof actual === "number"
      && actual >= (v[0] as number) && actual <= (v[1] as number);
  }
  if (e === "exists") return actual !== undefined && actual !== null;
  // bare literal → equals
  return actual === parseLiteral(e);
};

export const evalCell = (actual: unknown, expr: string): boolean => {
  if (!expr) return true;
  // split on " and " (lowest precedence supported)
  const parts = expr.split(/\s+and\s+/i);
  return parts.every((p) => evalAtom(actual, p));
};

// ─── Row evaluation
interface RowMatch {
  matched: boolean;
  perInput: Array<{ field: string; expr: string; actual: unknown; matched: boolean }>;
  output: Record<string, unknown>;
}

const evalRow = (
  row: JdmRule, inputs: JdmInputField[], outputs: { id: string; field: string }[],
  fact: Record<string, unknown>,
): RowMatch => {
  const perInput = inputs.map((i) => {
    const expr = row[i.id] ?? "";
    const actual = get(fact, i.field);
    return { field: i.field, expr, actual, matched: evalCell(actual, expr) };
  });
  const matched = perInput.every((p) => p.matched);
  const output: Record<string, unknown> = {};
  for (const o of outputs) output[o.field] = parseLiteral(row[o.id] ?? "");
  return { matched, perInput, output };
};

// ─── Decision table → matched conditions for hit reporting
const tableMatch = (
  table: JdmDecisionTableContent, fact: Record<string, unknown>,
): { fired: boolean; rows: RowMatch[]; output: Record<string, unknown> } => {
  const rows = table.rules.map((r) => evalRow(r, table.inputs, table.outputs, fact));
  const matchedRows = rows.filter((r) => r.matched);
  if (!matchedRows.length) return { fired: false, rows, output: {} };
  if (table.hitPolicy === "first") return { fired: true, rows, output: matchedRows[0].output };
  // collect: merge outputs, attach array
  const merged: Record<string, unknown> = { _matchedRows: matchedRows.map((r) => r.output) };
  for (const r of matchedRows) Object.assign(merged, r.output);
  return { fired: true, rows, output: merged };
};

// ─── Public: evaluate a JDM graph against a fact
export interface JdmEvalResult {
  fired: boolean;
  output: Record<string, unknown>;
  matched: MatchedCondition[];
  confidence: number;
}

export const evaluateGraph = (graph: JdmGraph, fact: Record<string, unknown>): JdmEvalResult => {
  const tables = graph.nodes.filter((n) => n.type === "decisionTableNode" && n.content);
  if (!tables.length) return { fired: false, output: {}, matched: [], confidence: 0 };

  let fired = false;
  let combinedOutput: Record<string, unknown> = {};
  const matched: MatchedCondition[] = [];
  let total = 0; let hits = 0;

  for (const node of tables) {
    const table = node.content!;
    const res = tableMatch(table, fact);
    fired = fired || res.fired;
    Object.assign(combinedOutput, res.output);

    // For confidence: count matched cells across ALL rows' inputs (skip wildcard cells).
    for (const row of res.rows) {
      for (const p of row.perInput) {
        if (!p.expr) continue; // wildcard doesn't contribute
        total += 1;
        if (p.matched) hits += 1;
        matched.push({
          field: p.field,
          operator: "eq", // legacy field; expression carried in `value`
          value: p.expr,
          actual: p.actual,
          matched: p.matched,
          weight: 1,
        });
      }
    }
  }
  const confidence = total ? hits / total : (fired ? 1 : 0);
  return { fired, output: combinedOutput, matched, confidence };
};

export const evaluateRuleJdm = (
  rule: Rule, fact: Record<string, unknown>, subjectId: string,
  mode: "live" | "sandbox" = "live",
): RuleHit | null => {
  if (!rule.content) return null;
  const r = evaluateGraph(rule.content, fact);
  if (!r.fired || r.confidence < rule.threshold) return null;
  return {
    id: crypto.randomUUID(),
    rule_id: rule.id,
    rule_version: rule.version,
    rule_name: rule.name,
    severity: rule.severity,
    action: rule.action,
    scope: rule.scope,
    subject_id: subjectId,
    confidence: r.confidence,
    matched_conditions: r.matched,
    evaluated_at: new Date().toISOString(),
    mode,
  };
};

// ─── Auto-convert legacy condition tree → JDM decision table
const legacyOpToCell = (op: string, value: unknown): string => {
  const lit = (v: unknown): string => {
    if (typeof v === "string") return JSON.stringify(v);
    if (typeof v === "number" || typeof v === "boolean") return String(v);
    if (v === null || v === undefined) return "null";
    return JSON.stringify(v);
  };
  switch (op) {
    case "eq":  return `== ${lit(value)}`;
    case "neq": return `!= ${lit(value)}`;
    case "gt":  return `> ${lit(value)}`;
    case "gte": return `>= ${lit(value)}`;
    case "lt":  return `< ${lit(value)}`;
    case "lte": return `<= ${lit(value)}`;
    case "in":  return `in ${JSON.stringify(value)}`;
    case "not_in": return `not in ${JSON.stringify(value)}`;
    case "between": return `between ${JSON.stringify(value)}`;
    case "contains": return `contains ${lit(value)}`;
    case "exists": return "exists";
    default: return "";
  }
};

const flattenLeaves = (node: RuleNode): Array<{ field: string; op: string; value: unknown }> => {
  if (node.kind === "condition") return [{ field: node.field, op: node.operator, value: node.value }];
  return node.children.flatMap(flattenLeaves);
};

/**
 * Convert a legacy condition tree into a single decision-table JDM graph.
 * - AND root → one row, columns = leaves
 * - OR root  → one row per OR child group (each AND-group becomes a row)
 * - Mixed    → flattens to AND row (best-effort; visible to author for refinement)
 */
export const conditionTreeToJdm = (root: RuleConditionGroup, ruleName: string): JdmGraph => {
  // Build distinct input columns from all referenced fields, in stable order.
  const allLeaves = flattenLeaves(root);
  const fields = Array.from(new Set(allLeaves.map((l) => l.field)));
  const inputs: JdmInputField[] = fields.map((f) => ({
    id: `in_${f.replace(/\W+/g, "_")}`,
    field: f,
    name: f,
  }));
  const inputIdByField = new Map(inputs.map((i) => [i.field, i.id]));

  // Determine rows
  type RowSpec = Array<{ field: string; op: string; value: unknown }>;
  let rowSpecs: RowSpec[] = [];
  if (root.combinator === "OR") {
    rowSpecs = root.children.map((child) =>
      child.kind === "group" ? flattenLeaves(child) : [{ field: child.field, op: child.operator, value: child.value }],
    );
  } else {
    rowSpecs = [allLeaves];
  }

  const outputs = [{ id: "out_matched", field: "matched", name: "matched" }];
  const rules: JdmRule[] = rowSpecs.map((spec, idx) => {
    const row: JdmRule = { _id: `r_${idx}`, out_matched: "true" };
    for (const cond of spec) {
      const inId = inputIdByField.get(cond.field);
      if (inId) row[inId] = legacyOpToCell(cond.op, cond.value);
    }
    return row;
  });

  const inputNode: JdmGraph["nodes"][number] = {
    id: "input_1", type: "inputNode", name: "Input",
    position: { x: 80, y: 80 },
  };
  const tableNode: JdmGraph["nodes"][number] = {
    id: "table_1", type: "decisionTableNode", name: ruleName,
    position: { x: 360, y: 80 },
    content: { hitPolicy: root.combinator === "OR" ? "collect" : "first", inputs, outputs, rules },
  };
  const outputNode: JdmGraph["nodes"][number] = {
    id: "output_1", type: "outputNode", name: "Output",
    position: { x: 720, y: 80 },
  };
  return {
    nodes: [inputNode, tableNode, outputNode],
    edges: [
      { id: "e1", sourceId: "input_1", targetId: "table_1" },
      { id: "e2", sourceId: "table_1", targetId: "output_1" },
    ],
  };
};

// Empty starter graph
export const emptyJdmGraph = (): JdmGraph => ({
  nodes: [
    { id: "input_1", type: "inputNode", name: "Input", position: { x: 80, y: 80 } },
    {
      id: "table_1", type: "decisionTableNode", name: "Decisions",
      position: { x: 360, y: 80 },
      content: {
        hitPolicy: "first",
        inputs: [{ id: "in_amount", field: "amount", name: "amount" }],
        outputs: [{ id: "out_matched", field: "matched", name: "matched" }],
        rules: [{ _id: "r_0", in_amount: "", out_matched: "true" }],
      },
    },
    { id: "output_1", type: "outputNode", name: "Output", position: { x: 720, y: 80 } },
  ],
  edges: [
    { id: "e1", sourceId: "input_1", targetId: "table_1" },
    { id: "e2", sourceId: "table_1", targetId: "output_1" },
  ],
});
