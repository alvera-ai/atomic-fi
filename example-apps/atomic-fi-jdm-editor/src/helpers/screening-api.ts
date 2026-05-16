import { atomicFiClient } from './clients';

export type ScreeningEntityType =
  | 'account-holder'
  | 'beneficial-owner'
  | 'counterparty'
  | 'payment-account';

export const SCREENING_ENTITY_TYPES: ScreeningEntityType[] = [
  'account-holder',
  'beneficial-owner',
  'counterparty',
  'payment-account',
];

export const SCREENING_ENTITY_LABELS: Record<ScreeningEntityType, string> = {
  'account-holder': 'Account holder',
  'beneficial-owner': 'Beneficial owner',
  counterparty: 'Counterparty',
  'payment-account': 'Payment account',
};

// Response shape mirrors AtomicFi.ComplianceScreening (facts-only, no verdict).
export type ScreeningResponse = {
  compliance_screening: {
    screening_status: 'pending' | string;
    screened_entity_type: 'individual' | 'company' | 'payment_account';
    sanctions_matches?: unknown[];
    blocklist_matches?: unknown[];
    [key: string]: unknown;
  };
};

export async function previewScreen(
  entityType: ScreeningEntityType,
  payload: unknown,
): Promise<ScreeningResponse> {
  const { data } = await atomicFiClient.post<ScreeningResponse>(
    `/api/compliance-screenings/screen-${entityType}`,
    payload,
  );
  return data;
}
