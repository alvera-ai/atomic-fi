import type { AccountHolderResponse } from "@/api/types";
import { getRequiredDocs, type ChecklistDoc } from "@/components/onboarding/document-checklist";

// uid helper mirrors fixtures.ts (id format: "00000065-aaaa-bbbb-cccc-000000000065")
const uid = (n: number) => `${n.toString(16).padStart(8, "0")}-aaaa-bbbb-cccc-${n.toString(16).padStart(12, "0")}`;
const daysAgo = (n: number) => new Date(Date.now() - n * 86_400_000).toISOString();

// Pre-seeded checklist state per holder id. Falls back to required defaults.
const SEED: Record<string, Partial<Record<string, Partial<ChecklistDoc>>>> = {
  // 101 Acme Robotics — fully approved
  [uid(101)]: {
    incorporation: { status: "approved", filename: "acme_certificate.pdf", uploaded_at: daysAgo(115) },
    registered_address: { status: "approved", filename: "utility_bill_acme.pdf", uploaded_at: daysAgo(110) },
    ubo_declaration: { status: "approved", filename: "acme_ubo.pdf", uploaded_at: daysAgo(108) },
    ubo_id: { status: "approved", filename: "ubo_passports.zip", uploaded_at: daysAgo(108) },
    sanctions: { status: "approved", filename: "screening_2026Q1.pdf", uploaded_at: daysAgo(30) },
  },
  // 103 Nordic Freight — partial
  [uid(103)]: {
    incorporation: { status: "submitted", filename: "articles_of_incorporation.pdf", uploaded_at: daysAgo(2) },
    registered_address: { status: "submitted", filename: "lease_nordic.pdf", uploaded_at: daysAgo(2) },
    ubo_declaration: { status: "required" },
    ubo_id: { status: "required" },
    sanctions: { status: "approved", filename: "screening_nordic.pdf", uploaded_at: daysAgo(1) },
  },
  // 104 Jin Wei (individual, low risk)
  [uid(104)]: {
    photo_id: { status: "approved", filename: "passport_jin_wei.pdf", uploaded_at: daysAgo(295) },
    proof_of_address: { status: "approved", filename: "bank_statement_jw.pdf", uploaded_at: daysAgo(60) },
    sanctions: { status: "approved", filename: "screening_jw.pdf", uploaded_at: daysAgo(60) },
  },
  // 105 Cairo Trade — high risk, needs EDD
  [uid(105)]: {
    incorporation: { status: "submitted", filename: "cairo_incorporation.pdf", uploaded_at: daysAgo(50) },
    registered_address: { status: "expired", filename: "cairo_address_2024.pdf", uploaded_at: daysAgo(400) },
    ubo_declaration: { status: "submitted", filename: "ubo_chart_cairotrade.png", uploaded_at: daysAgo(58) },
    ubo_id: { status: "rejected", filename: "ubo_id_unclear.jpg", uploaded_at: daysAgo(58) },
    sanctions: { status: "submitted", filename: "screening_cairo.pdf", uploaded_at: daysAgo(3) },
  },
  // 107 Maria González — individual, high risk, rejected ID
  [uid(107)]: {
    photo_id: { status: "rejected", filename: "id_expired.jpg", uploaded_at: daysAgo(8) },
    proof_of_address: { status: "required" },
    sanctions: { status: "submitted", filename: "screening_mg.pdf", uploaded_at: daysAgo(7) },
    source_of_funds: { status: "required" },
  },
};

export function seedChecklist(holder: AccountHolderResponse, txVolume = 0): ChecklistDoc[] {
  const required = getRequiredDocs(holder, { totalTransactionVolume: txVolume });
  const overrides = SEED[holder.id] ?? {};
  return required.map((d) => ({ ...d, ...(overrides[d.key] ?? {}) }));
}
