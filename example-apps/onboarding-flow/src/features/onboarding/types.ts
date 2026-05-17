// Application status enum
export type ApplicationStatus =
  | "DRAFT"
  | "SUBMITTED"
  | "UNDER_REVIEW"
  | "ACTION_REQUIRED"
  | "APPROVED"
  | "UNABLE_TO_PROCEED";

// Onboarding method enum
export type OnboardingMethod = "UPLOAD_PREFILL" | "MANUAL";

// Document status enum
export type DocumentStatus = "UPLOADED" | "PROCESSING" | "EXTRACTED" | "NEEDS_ATTENTION";

// Document types for categorized upload
export type DocumentType =
  | "TRADE_LICENSE"
  | "MEMORANDUM_OF_ASSOCIATION"
  | "CERTIFICATE_OF_INCORPORATION"
  | "PASSPORT"
  | "EMIRATES_ID"
  | "PROOF_OF_ADDRESS"
  | "BANK_STATEMENT"
  | "OTHER";

// Verification
export type VerificationFlag =
  | "ILLEGIBLE"
  | "FAKE_SUSPECTED"
  | "IRRELEVANT"
  | "WRONG_FORMAT"
  | "EXPIRED";

export interface VerificationResult {
  status: "PASS" | "WARN" | "FAIL";
  flags: VerificationFlag[];
  message: string;
}

// Upload mode
export type UploadMode = "BULK" | "INDIVIDUAL";

// Document interface
export interface Document {
  file_id: string;
  doc_type: DocumentType;
  filename: string;
  status: DocumentStatus;
  uploaded_at: string;
  verification?: VerificationResult;
}

// Field provenance for tracking extracted data
export interface FieldProvenance {
  source_doc_type: DocumentType;
  page_number: number;
  confidence: number; // 0-100
  snippet: string;
}

// Director interface
export interface Director {
  id: string;
  full_name: string;
  nationality: string;
  date_of_birth: string;
  passport_number: string;
  email: string;
  phone: string;
  is_signatory: boolean;
}

// Signatory interface
export interface Signatory {
  id: string;
  full_name: string;
  role: string;
  email: string;
  phone: string;
}

// Ultimate Beneficial Owner interface
export interface UBO {
  id: string;
  full_name: string;
  nationality: string;
  date_of_birth: string;
  ownership_percentage: number;
  passport_number: string;
  residential_address: string;
}

// Business profile
export interface BusinessProfile {
  legal_name?: string;
  trade_name?: string;
  license_number?: string;
  license_expiry?: string;
  jurisdiction?: string;
  entity_type?: string;
  incorporation_date?: string;
}

// Address interface
export interface Address {
  id: string;
  type: "REGISTERED" | "OPERATING" | "CORRESPONDENCE";
  line1: string;
  line2?: string;
  city: string;
  emirate?: string;
  country: string;
  postal_code?: string;
}

// Business contact
export interface BusinessContact {
  id: string;
  type: "PRIMARY" | "COMPLIANCE" | "FINANCE";
  full_name: string;
  email: string;
  phone: string;
  role: string;
}

// Business activity
export interface BusinessActivity {
  primary_activity?: string;
  secondary_activities?: string[];
  purpose_of_account?: string;
  source_of_funds?: string;
}

// Expected transfer behavior
export interface TransferBehavior {
  expected_monthly_volume_usd?: number;
  expected_monthly_transactions?: number;
  primary_transfer_purpose?: string;
  expected_counterparties?: string[];
  high_risk_jurisdictions?: boolean;
}

// Ownership structure
export interface OwnershipStructure {
  is_subsidiary?: boolean;
  parent_company_name?: string;
  parent_company_jurisdiction?: string;
  ownership_chart_uploaded?: boolean;
}

// Submission confirmations
export interface SubmissionConfirmations {
  confirm_accuracy: boolean;
  confirm_authority: boolean;
}

// Ops note
export interface OpsNote {
  id: string;
  author: string;
  content: string;
  created_at: string;
}

// Main Application interface
export interface Application {
  application_id: string;
  status: ApplicationStatus;
  onboarding_method: OnboardingMethod;
  created_at: string;
  updated_at: string;
  current_step: number;
  completed_steps: number[];
  upload_mode?: UploadMode;

  // Nested data
  business_profile: BusinessProfile;
  addresses: Address[];
  business_contacts: BusinessContact[];
  business_activity: BusinessActivity;
  transfer_behavior: TransferBehavior;
  ownership_structure: OwnershipStructure;
  directors: Director[];
  signatories: Signatory[];
  ubos: UBO[];
  documents: Document[];
  field_provenance: Record<string, FieldProvenance>;
  submission_confirmations: SubmissionConfirmations;
  ops_notes: OpsNote[];

  api_result?: {
    accountHolderId: string;
    legalEntityId: string;
    documentIds: string[];
    kycRequirementId: string;
  };
}

// Step definition
export interface StepDefinition {
  id: number;
  title: string;
  path: string;
  description: string;
}

// All onboarding steps
