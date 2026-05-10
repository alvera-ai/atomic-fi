import { accountHolders, transactions } from "@/data/fixtures";

export type CaseType = "transaction_flag" | "onboarding_review" | "sanctions_match" | "rule_breach";
export type CaseStatus = "open" | "in_progress" | "pending_customer" | "escalated" | "closed";
export type CasePriority = "critical" | "high" | "medium" | "low";
export type CaseSourceType = "transaction" | "account_holder";

export interface CaseNote {
  author: string;
  text: string;
  timestamp: string;
}

export interface Case {
  id: string;
  type: CaseType;
  status: CaseStatus;
  priority: CasePriority;
  title: string;
  description: string;
  source_id: string;
  source_type: CaseSourceType;
  assigned_to: string;
  created_at: string;
  updated_at: string;
  due_date: string;
  notes: CaseNote[];
}

const ASSIGNEES = [
  "Alex Ortega",
  "Priya Shah",
  "Marcus Chen",
  "Sofía Reyes",
  "Liam O'Connor",
  "Yuki Tanaka",
];

const daysFromNow = (n: number) => new Date(Date.now() + n * 86_400_000).toISOString();
const daysAgo = (n: number) => new Date(Date.now() - n * 86_400_000).toISOString();

const tx = (i: number) => transactions[i % transactions.length];
const hl = (i: number) => accountHolders[i % accountHolders.length];

const seed: Case[] = [
  {
    id: "case_0001",
    type: "rule_breach",
    status: "open",
    priority: "critical",
    title: "High-value transfer to blocked counterparty",
    description: "Live rule 'Transfer to blocked counterparty' fired with confidence 0.96.",
    source_id: tx(0).id,
    source_type: "transaction",
    assigned_to: ASSIGNEES[0],
    created_at: daysAgo(1),
    updated_at: daysAgo(0),
    due_date: daysFromNow(1),
    notes: [
      { author: "System", text: "Auto-created from rule breach.", timestamp: daysAgo(1) },
      { author: ASSIGNEES[0], text: "Reviewing counterparty status with ops team.", timestamp: daysAgo(0) },
    ],
  },
  {
    id: "case_0002",
    type: "sanctions_match",
    status: "in_progress",
    priority: "high",
    title: "Potential sanctions match on debtor name",
    description: "Screening returned a potential match against OFAC SDN list (score 0.82).",
    source_id: tx(3).id,
    source_type: "transaction",
    assigned_to: ASSIGNEES[1],
    created_at: daysAgo(2),
    updated_at: daysAgo(1),
    due_date: daysFromNow(2),
    notes: [
      { author: ASSIGNEES[1], text: "Requested additional KYC documents.", timestamp: daysAgo(1) },
    ],
  },
  {
    id: "case_0003",
    type: "onboarding_review",
    status: "pending_customer",
    priority: "medium",
    title: "Missing proof of address for new applicant",
    description: "KYC requirement 'proof_of_address' is outstanding.",
    source_id: hl(2).id,
    source_type: "account_holder",
    assigned_to: ASSIGNEES[2],
    created_at: daysAgo(4),
    updated_at: daysAgo(2),
    due_date: daysFromNow(5),
    notes: [
      { author: ASSIGNEES[2], text: "Outreach email sent — awaiting customer response.", timestamp: daysAgo(2) },
    ],
  },
  {
    id: "case_0004",
    type: "transaction_flag",
    status: "open",
    priority: "high",
    title: "Manually flagged: unusual cross-border pattern",
    description: "Analyst flagged 4 outbound transfers to new counterparties within 24h.",
    source_id: tx(5).id,
    source_type: "transaction",
    assigned_to: ASSIGNEES[3],
    created_at: daysAgo(0),
    updated_at: daysAgo(0),
    due_date: daysFromNow(3),
    notes: [],
  },
  {
    id: "case_0005",
    type: "rule_breach",
    status: "escalated",
    priority: "critical",
    title: "Holder over 1M USD with high-risk country",
    description: "Live rule 'High-risk holder over 1M USD' fired with confidence 1.0.",
    source_id: hl(4).id,
    source_type: "account_holder",
    assigned_to: ASSIGNEES[0],
    created_at: daysAgo(3),
    updated_at: daysAgo(1),
    due_date: daysFromNow(1),
    notes: [
      { author: ASSIGNEES[0], text: "Escalated to MLRO for sign-off.", timestamp: daysAgo(1) },
    ],
  },
  {
    id: "case_0006",
    type: "onboarding_review",
    status: "in_progress",
    priority: "medium",
    title: "Beneficial owner verification pending",
    description: "UBO chain incomplete; missing one director identity document.",
    source_id: hl(0).id,
    source_type: "account_holder",
    assigned_to: ASSIGNEES[4],
    created_at: daysAgo(6),
    updated_at: daysAgo(2),
    due_date: daysFromNow(7),
    notes: [
      { author: ASSIGNEES[4], text: "Started UBO trace via corporate registry.", timestamp: daysAgo(2) },
    ],
  },
  {
    id: "case_0007",
    type: "transaction_flag",
    status: "closed",
    priority: "low",
    title: "Duplicate payment instruction — resolved",
    description: "Customer confirmed duplicate; second instruction reversed.",
    source_id: tx(7).id,
    source_type: "transaction",
    assigned_to: ASSIGNEES[5],
    created_at: daysAgo(10),
    updated_at: daysAgo(8),
    due_date: daysAgo(7),
    notes: [
      { author: ASSIGNEES[5], text: "Reversal posted; case closed.", timestamp: daysAgo(8) },
    ],
  },
  {
    id: "case_0008",
    type: "sanctions_match",
    status: "open",
    priority: "high",
    title: "PEP exposure detected on new beneficial owner",
    description: "Newly added UBO matches PEP list — review required.",
    source_id: hl(6).id,
    source_type: "account_holder",
    assigned_to: ASSIGNEES[1],
    created_at: daysAgo(1),
    updated_at: daysAgo(0),
    due_date: daysFromNow(2),
    notes: [],
  },
];

let cases: Case[] = [...seed];
const subscribers = new Set<() => void>();
const notify = () => subscribers.forEach((s) => s());

const delay = <T,>(v: T, ms = 150) => new Promise<T>((r) => setTimeout(() => r(v), ms));

export const listCases = () => delay([...cases]);

export const listCasesBySource = (sourceId: string) =>
  delay(cases.filter((c) => c.source_id === sourceId));

export const getCaseById = (id: string) => delay(cases.find((c) => c.id === id));

export const createCase = (input: Omit<Case, "id" | "created_at" | "updated_at" | "notes"> & { notes?: CaseNote[] }): Promise<Case> => {
  const now = new Date().toISOString();
  const created: Case = {
    id: `case_${Math.random().toString(16).slice(2, 8)}`,
    notes: input.notes ?? [],
    ...input,
    created_at: now,
    updated_at: now,
  };
  cases = [created, ...cases];
  notify();
  return delay(created);
};

export const updateCase = (id: string, patch: Partial<Case>): Promise<Case> => {
  cases = cases.map((c) => (c.id === id ? { ...c, ...patch, updated_at: new Date().toISOString() } : c));
  notify();
  return delay(cases.find((c) => c.id === id)!);
};

export const addCaseNote = (id: string, note: CaseNote): Promise<Case> => {
  cases = cases.map((c) =>
    c.id === id ? { ...c, notes: [...c.notes, note], updated_at: new Date().toISOString() } : c,
  );
  notify();
  return delay(cases.find((c) => c.id === id)!);
};

export const subscribeCases = (fn: () => void) => {
  subscribers.add(fn);
  return () => subscribers.delete(fn);
};

export const ASSIGNEE_OPTIONS = ASSIGNEES;
