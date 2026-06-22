// Shapes returned by the atomic-fi stateless preview-screening endpoints.
// Fields are optional/loose on purpose: the API is the source of truth and
// the result UI renders defensively against whatever a row actually contains.

export type ScreeningType = 'sanctions' | 'pep' | 'aml' | 'adverse_media' | (string & {})

export interface SanctionsMatchAddress {
  city?: string | null
  country?: string | null
  region?: string | null
  postal_code?: string | null
}

export interface SanctionsMatch {
  matched_name?: string | null
  matched_entity_type?: string | null // 'person' | 'business'
  match_score?: number | null // 0..1
  source_list?: string | null // e.g. 'us_ofac'
  source_id?: string | null
  false_positive_qualifier?: string | null
  addresses?: SanctionsMatchAddress[] | null
  person_data?: { dob?: string | null; given_name?: string | null; family_name?: string | null } | null
  source_data?: { title?: string | null; program?: string[] | null; remarks?: string | null } | null
  [key: string]: unknown
}

export interface ComplianceScreening {
  id?: string | null
  screening_type?: ScreeningType | null
  screening_status?: string | null
  screening_score?: number | string | null
  screened_entity_name?: string | null
  screened_entity_type?: string | null
  match_count?: number | null
  sanctions_screening_status?: 'cleared' | 'pending' | 'match' | 'failed' | null
  sanctions_matches?: SanctionsMatch[] | null
  pep_indicator?: boolean | null
  pep_list_name?: string | null
  aml_risk_score?: number | string | null
  aml_high_risk_country?: string | null
  aml_control_flag?: boolean | null
  manual_review_required?: boolean | null
  escalation_level?: number | null
  review_notes?: string | null
  [key: string]: unknown
}

export interface ScreenResponse {
  data: ComplianceScreening[]
  meta?: Record<string, unknown>
}
