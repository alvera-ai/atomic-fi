import { accountHolders, transactions } from "@/data/fixtures";
import { updateCase, listCases, type Case } from "@/api/cases";

export type OutreachStatus = "sent" | "responded" | "overdue";
export type OutreachSubjectType = "transaction" | "account_holder";

export interface OutreachMessage {
  id: string;
  subject_type: OutreachSubjectType;
  subject_id: string;
  to_email: string;
  subject: string;
  body: string;
  template: string;
  document_requests: string[];
  sent_by: string;
  sent_at: string;
  status: OutreachStatus;
  responded_at?: string | null;
  case_id?: string | null;
}

export const OUTREACH_TEMPLATES = [
  {
    id: "additional_documentation",
    label: "Request additional documentation",
    subject: "Additional documentation required",
    body:
      "Hello [CUSTOMER_NAME],\n\nIn order to complete the review of transaction [TRANSACTION_ID], we kindly ask you to provide the documents listed below.\n\nThank you,\nCompliance Team",
  },
  {
    id: "clarify_purpose",
    label: "Clarify transaction purpose",
    subject: "Clarification needed for a recent transaction",
    body:
      "Hello [CUSTOMER_NAME],\n\nWe noticed transaction [TRANSACTION_ID] and would like to better understand its purpose. Could you please briefly describe the nature and intent of this payment?\n\nThank you,\nCompliance Team",
  },
  {
    id: "source_of_funds",
    label: "Provide source of funds",
    subject: "Source of funds verification",
    body:
      "Hello [CUSTOMER_NAME],\n\nAs part of our ongoing monitoring, we need to verify the source of funds related to transaction [TRANSACTION_ID]. Please share supporting documentation (e.g. payslips, sale agreements, bank statements).\n\nThank you,\nCompliance Team",
  },
  {
    id: "identity_verification",
    label: "Identity verification required",
    subject: "Identity verification required",
    body:
      "Hello [CUSTOMER_NAME],\n\nWe need to confirm your identity before we can proceed. Please upload a valid government-issued ID and a recent proof of address.\n\nThank you,\nCompliance Team",
  },
  { id: "custom", label: "Custom (blank)", subject: "", body: "" },
] as const;

export const DOCUMENT_REQUEST_OPTIONS = [
  "Proof of Address",
  "Bank Statement",
  "Business Registration",
  "Government-issued ID",
  "Source of Funds Statement",
  "Tax Identification Document",
  "Beneficial Ownership Disclosure",
  "Invoice or Contract",
];

const daysAgo = (n: number) => new Date(Date.now() - n * 86_400_000).toISOString();

const seed: OutreachMessage[] = [
  {
    id: "or_0001",
    subject_type: "transaction",
    subject_id: transactions[0]?.id ?? "tx_seed",
    to_email: accountHolders[0]?.email ?? "ops@acme.io",
    subject: "Source of funds verification",
    body:
      "Hello Acme Robotics,\n\nAs part of our ongoing monitoring, we need to verify the source of funds related to a recent transaction. Please share supporting documentation.\n\nThank you,\nCompliance Team",
    template: "source_of_funds",
    document_requests: ["Bank Statement", "Source of Funds Statement"],
    sent_by: "Alex Ortega",
    sent_at: daysAgo(6),
    status: "responded",
    responded_at: daysAgo(3),
  },
  {
    id: "or_0002",
    subject_type: "transaction",
    subject_id: transactions[0]?.id ?? "tx_seed",
    to_email: accountHolders[0]?.email ?? "ops@acme.io",
    subject: "Clarification needed for a recent transaction",
    body:
      "Hello Acme Robotics,\n\nWe noticed a transaction and would like to better understand its purpose. Could you please briefly describe the nature and intent of this payment?\n\nThank you,\nCompliance Team",
    template: "clarify_purpose",
    document_requests: [],
    sent_by: "Priya Shah",
    sent_at: daysAgo(2),
    status: "sent",
  },
  {
    id: "or_0003",
    subject_type: "transaction",
    subject_id: transactions[0]?.id ?? "tx_seed",
    to_email: accountHolders[0]?.email ?? "ops@acme.io",
    subject: "Additional documentation required",
    body:
      "Hello Acme Robotics,\n\nWe still need a few documents to close our review. Please upload them at your earliest convenience.\n\nThank you,\nCompliance Team",
    template: "additional_documentation",
    document_requests: ["Proof of Address", "Business Registration"],
    sent_by: "Marcus Chen",
    sent_at: daysAgo(12),
    status: "overdue",
  },
];

let store: OutreachMessage[] = [...seed];
const subscribers = new Set<() => void>();
const notify = () => subscribers.forEach((fn) => fn());

const delay = <T,>(v: T, ms = 150) => new Promise<T>((r) => setTimeout(() => r(v), ms));

export const listOutreach = (subjectType: OutreachSubjectType, subjectId: string) =>
  delay(store.filter((m) => m.subject_type === subjectType && m.subject_id === subjectId)
    .sort((a, b) => b.sent_at.localeCompare(a.sent_at)));

export const sendOutreach = async (
  input: Omit<OutreachMessage, "id" | "sent_at" | "status" | "case_id"> & { case_id?: string | null },
): Promise<OutreachMessage> => {
  const created: OutreachMessage = {
    ...input,
    id: `or_${Math.random().toString(16).slice(2, 8)}`,
    sent_at: new Date().toISOString(),
    status: "sent",
    case_id: input.case_id ?? null,
  };
  store = [created, ...store];

  // Auto-link to first open case for this subject and move it to pending_customer.
  try {
    const allCases = await listCases();
    const linked: Case | undefined = allCases.find(
      (c) => c.source_id === input.subject_id && c.status !== "closed",
    );
    if (linked) {
      await updateCase(linked.id, { status: "pending_customer" });
      store = store.map((m) => (m.id === created.id ? { ...m, case_id: linked.id } : m));
    }
  } catch {
    /* noop in mock */
  }

  notify();
  return created;
};

export const subscribeOutreach = (fn: () => void) => {
  subscribers.add(fn);
  return () => subscribers.delete(fn);
};
