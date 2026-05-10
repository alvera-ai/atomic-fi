import type { Rule } from "@/api/types";

const now = "2026-05-02T12:00:00Z";
const id = (n: number) => `${n.toString(16).padStart(8, "0")}-rule-bbbb-cccc-${n.toString(16).padStart(12, "0")}`;

export const seedRules: Rule[] = [
  {
    id: id(1),
    name: "Transfer to blocked counterparty",
    description: "Any transaction whose creditor counterparty is blocked.",
    scope: "transaction",
    status: "live",
    severity: "critical",
    action: "block",
    threshold: 0.5,
    when: {
      id: "g1", kind: "group", combinator: "AND",
      children: [
        { id: "c1", kind: "condition", field: "creditor_counterparty.status", operator: "eq", value: "blocked", weight: 10 },
      ],
    },
    tags: ["sanctions", "blocklist"],
    created_at: now, updated_at: now, created_by: "system", version: 1,
  },
  {
    id: id(2),
    name: "High-risk holder over 1M USD",
    description: "USD transfer ≥ 1,000,000 by a high or prohibited-risk holder.",
    scope: "transaction",
    status: "live",
    severity: "high",
    action: "review",
    threshold: 0.6,
    when: {
      id: "g2", kind: "group", combinator: "AND",
      children: [
        { id: "c1", kind: "condition", field: "currency", operator: "eq", value: "USD", weight: 3 },
        { id: "c2", kind: "condition", field: "amount", operator: "gte", value: 1_000_000_00, weight: 5 },
        { id: "c3", kind: "condition", field: "account_holder.risk_level", operator: "in", value: ["high", "prohibited"], weight: 8 },
      ],
    },
    tags: ["aml", "high-value"],
    created_at: now, updated_at: now, created_by: "system", version: 1,
  },
  {
    id: id(3),
    name: "Sanctioned creditor jurisdiction",
    description: "Creditor counterparty is in a high-risk jurisdiction.",
    scope: "transaction",
    status: "live",
    severity: "high",
    action: "review",
    threshold: 0.5,
    when: {
      id: "g3", kind: "group", combinator: "AND",
      children: [
        { id: "c1", kind: "condition", field: "creditor_counterparty.country", operator: "in", value: ["RU", "KP", "IR", "SY"], weight: 10 },
      ],
    },
    tags: ["sanctions", "geography"],
    created_at: now, updated_at: now, created_by: "system", version: 1,
  },
  {
    id: id(4),
    name: "Screening match present",
    description: "Linked compliance screening status is match or potential_match.",
    scope: "transaction",
    status: "live",
    severity: "high",
    action: "review",
    threshold: 0.5,
    when: {
      id: "g4", kind: "group", combinator: "AND",
      children: [
        { id: "c1", kind: "condition", field: "latest_screening.status", operator: "in", value: ["match", "potential_match"], weight: 10 },
      ],
    },
    tags: ["screening"],
    created_at: now, updated_at: now, created_by: "system", version: 1,
  },
  {
    id: id(5),
    name: "Holder KYC not approved",
    description: "Account holder has not completed KYC.",
    scope: "account_holder",
    status: "live",
    severity: "medium",
    action: "flag",
    threshold: 0.5,
    when: {
      id: "g5", kind: "group", combinator: "AND",
      children: [
        { id: "c1", kind: "condition", field: "kyc_status", operator: "in", value: ["not_started", "in_progress", "on_hold", "rejected"], weight: 10 },
      ],
    },
    tags: ["kyc"],
    created_at: now, updated_at: now, created_by: "system", version: 1,
  },
  {
    id: id(6),
    name: "EDD required for high-risk holder",
    description: "High-risk holder with open KYC requirements or rejected document.",
    scope: "account_holder",
    status: "live",
    severity: "high",
    action: "review",
    threshold: 0.6,
    when: {
      id: "g6", kind: "group", combinator: "AND",
      children: [
        { id: "c1", kind: "condition", field: "risk_level", operator: "in", value: ["high", "prohibited"], weight: 6 },
        {
          id: "g6a", kind: "group", combinator: "OR",
          children: [
            { id: "c2", kind: "condition", field: "open_kyc_requirements_count", operator: "gt", value: 0, weight: 4 },
            { id: "c3", kind: "condition", field: "rejected_kyc_requirements_count", operator: "gt", value: 0, weight: 4 },
          ],
        },
      ],
    },
    tags: ["edd", "kyc"],
    created_at: now, updated_at: now, created_by: "system", version: 1,
  },
  {
    id: id(7),
    name: "Velocity: large transfers in 24h",
    description: "Sandbox preview — flags large USD transfers above 5M.",
    scope: "transaction",
    status: "sandbox",
    severity: "medium",
    action: "flag",
    threshold: 0.5,
    when: {
      id: "g7", kind: "group", combinator: "AND",
      children: [
        { id: "c1", kind: "condition", field: "amount", operator: "gt", value: 5_000_000_00, weight: 10 },
        { id: "c2", kind: "condition", field: "currency", operator: "eq", value: "USD", weight: 3 },
      ],
    },
    tags: ["velocity"],
    created_at: now, updated_at: now, created_by: "system", version: 1,
  },
  {
    id: id(8),
    name: "Card payment to suspended counterparty",
    description: "",
    scope: "transaction",
    status: "sandbox",
    severity: "critical",
    action: "block",
    threshold: 0.6,
    when: {
      id: "g8", kind: "group", combinator: "AND",
      children: [
        { id: "c1", kind: "condition", field: "transaction_type", operator: "eq", value: "card_payment", weight: 5 },
        { id: "c2", kind: "condition", field: "creditor_counterparty.status", operator: "eq", value: "suspended", weight: 10 },
      ],
    },
    tags: ["cards"],
    created_at: now, updated_at: now, created_by: "system", version: 1,
  },
  {
    id: id(9),
    name: "Legacy: any transfer over 100k",
    description: "Superseded by High-risk holder over 1M USD.",
    scope: "transaction",
    status: "archived",
    severity: "low",
    action: "flag",
    threshold: 0.5,
    when: {
      id: "g9", kind: "group", combinator: "AND",
      children: [
        { id: "c1", kind: "condition", field: "amount", operator: "gt", value: 100_000_00, weight: 10 },
      ],
    },
    tags: ["legacy"],
    created_at: now, updated_at: now, created_by: "system", version: 1,
  },
];
