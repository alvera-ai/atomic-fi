import type { TransactionResponse, TransactionStatus, TransactionType } from "@/api/types";
import {
  accountHolders,
  beneficialOwners,
  complianceScreenings,
  counterparties,
  documents,
  kycRequirements,
  ledgerAccountBalances,
  sanctionsMatches,
  transactions,
} from "@/data/fixtures";

export type CopilotToolStep = {
  tool: "search_tables" | "get_schema" | "get_related_tables" | "execute_query";
  args: Record<string, unknown>;
  resultPreview: string;
};

export type ResultColumn = { key: string; label: string };

export type CopilotResolution = {
  steps: CopilotToolStep[];
  rows: unknown[];
  txRows: TransactionResponse[]; // populated only when results are transactions
  columns: ResultColumn[];
  sql: string;
  explanation: string;
  primaryTable: string;
};

const TABLES: Record<string, () => unknown[]> = {
  transactions: () => transactions,
  account_holders: () => accountHolders,
  counterparties: () => counterparties,
  beneficial_owners: () => beneficialOwners,
  kyc_requirements: () => kycRequirements,
  documents: () => documents,
  compliance_screenings: () => complianceScreenings,
  sanctions_matches: () => sanctionsMatches,
  ledger_account_balances: () => ledgerAccountBalances,
};

function matchAny(prompt: string, ...needles: string[]) {
  const p = prompt.toLowerCase();
  return needles.some((n) => p.includes(n));
}

function colsFromRow(row: Record<string, unknown>, max = 6): ResultColumn[] {
  return Object.keys(row).slice(0, max).map((k) => ({ key: k, label: k }));
}

export function resolveNlQuery(prompt: string): CopilotResolution {
  const p = prompt.trim();
  const lower = p.toLowerCase();

  // ── Cross-table patterns
  if (matchAny(lower, "high risk holder", "high-risk holder", "prohibited holder")) {
    const rows = accountHolders.filter((a) => a.risk_level === "high" || a.risk_level === "prohibited");
    return mk({
      prompt: p, primaryTable: "account_holders", tables: ["account_holders"],
      sql: "SELECT id, display_name, country, kyc_status, risk_level FROM account_holders\nWHERE risk_level IN ('high','prohibited');",
      rows, columns: [
        { key: "display_name", label: "name" }, { key: "country", label: "country" },
        { key: "kyc_status", label: "kyc" }, { key: "risk_level", label: "risk" },
      ],
      explanation: "Account holders flagged high or prohibited risk.",
    });
  }

  if (matchAny(lower, "blocked counterpart", "suspended counterpart", "sanction") && !lower.includes("transaction")) {
    const rows = counterparties.filter((c) => c.status !== "active");
    return mk({
      prompt: p, primaryTable: "counterparties", tables: ["counterparties"],
      sql: "SELECT id, display_name, country, status FROM counterparties WHERE status != 'active';",
      rows, columns: [
        { key: "display_name", label: "name" }, { key: "country", label: "country" }, { key: "status", label: "status" },
      ],
      explanation: "Counterparties not in active status.",
    });
  }

  if (matchAny(lower, "open kyc", "pending kyc", "kyc requirement")) {
    const rows = kycRequirements.filter((k) => k.status === "pending" || k.status === "submitted");
    return mk({
      prompt: p, primaryTable: "kyc_requirements", tables: ["kyc_requirements", "account_holders"],
      sql: "SELECT k.id, k.requirement_type, k.status, a.display_name AS account_holder\nFROM kyc_requirements k JOIN account_holders a ON a.id = k.account_holder_id\nWHERE k.status IN ('pending','submitted');",
      rows: rows.map((k) => ({
        id: k.id, requirement_type: k.requirement_type, status: k.status,
        account_holder: accountHolders.find((a) => a.id === k.account_holder_id)?.display_name ?? "—",
      })),
      columns: [
        { key: "requirement_type", label: "requirement" }, { key: "status", label: "status" },
        { key: "account_holder", label: "holder" },
      ],
      explanation: "Outstanding KYC requirements joined to account holders.",
    });
  }

  if (matchAny(lower, "sanctions match", "potential match", "ofac match")) {
    const rows = sanctionsMatches.map((m) => ({
      matched_name: m.matched_name, list_name: m.list_name, score: m.score,
      false_positive_qualifier: m.false_positive_qualifier ?? "—",
    }));
    return mk({
      prompt: p, primaryTable: "sanctions_matches", tables: ["sanctions_matches", "compliance_screenings"],
      sql: "SELECT matched_name, list_name, score, false_positive_qualifier FROM sanctions_matches;",
      rows, columns: colsFromRow(rows[0] ?? {}),
      explanation: "All sanctions match rows from screening results.",
    });
  }

  // ── Transaction patterns
  if (matchAny(lower, "sanction", "blocked counterparty", "blocked counterparties", "ofac")) {
    const blocked = new Set(["blocked", "under_review", "suspended"]);
    const cpIds = new Set(counterparties.filter((c) => blocked.has(c.status)).map((c) => c.id));
    const rows = transactions.filter((t) => t.creditor_counterparty_id && cpIds.has(t.creditor_counterparty_id));
    return mkTx({
      prompt: p, tables: ["transactions", "counterparties"], rows,
      sql: "SELECT t.* FROM transactions t\nJOIN counterparties c ON c.id = t.creditor_counterparty_id\nWHERE c.status IN ('blocked','under_review','suspended');",
      explanation: "Joined transactions to counterparties; filtered to non-active.",
    });
  }

  if (matchAny(lower, "rejected card", "card payment fail", "card declined")) {
    const rows = transactions.filter((t) => t.transaction_type === "card_payment" && t.status === "rejected");
    return mkTx({
      prompt: p, tables: ["transactions"], rows,
      sql: "SELECT * FROM transactions WHERE transaction_type = 'card_payment' AND status = 'rejected';",
      explanation: "Card payments with rejected status.",
    });
  }

  if (matchAny(lower, "pending", "stuck", "in flight") && matchAny(lower, "10k", "10,000", "10000", "large")) {
    const rows = transactions.filter((t) => t.status === "pending" && t.currency === "USD" && t.amount >= 1_000_000);
    return mkTx({
      prompt: p, tables: ["transactions"], rows,
      sql: "SELECT * FROM transactions WHERE status='pending' AND currency='USD' AND amount >= 1000000;",
      explanation: "Pending USD transactions ≥ $10,000.",
    });
  }

  const statuses: TransactionStatus[] = ["pending", "accepted", "settled", "rejected", "reversed", "cancelled"];
  const matchedStatus = statuses.find((s) => lower.includes(s));
  if (matchedStatus) {
    const rows = transactions.filter((t) => t.status === matchedStatus);
    return mkTx({
      prompt: p, tables: ["transactions"], rows,
      sql: `SELECT * FROM transactions WHERE status = '${matchedStatus}';`,
      explanation: `Filtered by status = ${matchedStatus}.`,
    });
  }

  const types: TransactionType[] = ["credit_transfer", "direct_debit", "card_payment", "refund", "reversal", "internal_transfer"];
  const matchedType = types.find((t) => lower.includes(t.replace("_", " ")) || lower.includes(t));
  if (matchedType) {
    const rows = transactions.filter((t) => t.transaction_type === matchedType);
    return mkTx({
      prompt: p, tables: ["transactions"], rows,
      sql: `SELECT * FROM transactions WHERE transaction_type = '${matchedType}';`,
      explanation: `Filtered by transaction_type = ${matchedType}.`,
    });
  }

  // Generic table mention → list table
  for (const [name, getter] of Object.entries(TABLES)) {
    if (lower.includes(name) || lower.includes(name.replace(/_/g, " "))) {
      const rows = getter().slice(0, 50);
      return mk({
        prompt: p, primaryTable: name, tables: [name],
        sql: `SELECT * FROM ${name} LIMIT 50;`,
        rows, columns: colsFromRow((rows[0] ?? {}) as Record<string, unknown>),
        explanation: `First 50 rows from ${name}.`,
      });
    }
  }

  // Fallback: substring search across transactions
  const rows = transactions.filter((t) =>
    [t.id, t.uetr, t.end_to_end_id, t.instruction_id, t.transaction_external_id]
      .filter(Boolean)
      .some((v) => (v as string).toLowerCase().includes(lower)),
  );
  return mkTx({
    prompt: p, tables: ["transactions"], rows,
    sql: `SELECT * FROM transactions WHERE id ILIKE '%${p}%' OR uetr ILIKE '%${p}%';`,
    explanation: "Substring search across transaction id-like fields.",
  });
}

function mkTx(args: { prompt: string; tables: string[]; sql: string; rows: TransactionResponse[]; explanation: string; }): CopilotResolution {
  return mk({
    prompt: args.prompt, primaryTable: "transactions", tables: args.tables, sql: args.sql,
    rows: args.rows as unknown as unknown[],
    columns: [
      { key: "id", label: "id" },
      { key: "transaction_type", label: "type" },
      { key: "status", label: "status" },
      { key: "amount", label: "amount" },
    ],
    explanation: args.explanation,
  });
}

function mk(args: {
  prompt: string;
  primaryTable: string;
  tables: string[];
  sql: string;
  rows: unknown[];
  columns: ResultColumn[];
  explanation: string;
}): CopilotResolution {
  const steps: CopilotToolStep[] = [
    { tool: "search_tables", args: { query: args.prompt }, resultPreview: `Found ${args.tables.length} candidate table(s): ${args.tables.join(", ")}` },
    { tool: "get_schema", args: { tables: args.tables }, resultPreview: `Loaded ${args.tables.length} schema(s)` },
    { tool: "get_related_tables", args: { tables: args.tables }, resultPreview: args.tables.length > 1 ? `Discovered FK ${args.tables[0]} → ${args.tables[1]}` : "No additional joins required." },
    { tool: "execute_query", args: { sql: args.sql }, resultPreview: `${args.rows.length} row(s) returned.` },
  ];
  const txRows = args.primaryTable === "transactions" ? (args.rows as unknown as TransactionResponse[]) : [];
  return { steps, rows: args.rows, txRows, columns: args.columns, sql: args.sql, explanation: args.explanation, primaryTable: args.primaryTable };
}
