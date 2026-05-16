import type { Application, OnboardingMethod } from "./types";

const STORAGE_KEY = "fintech_applications";

// Generate a random application ID
function generateApplicationId(): string {
  return `APP-${Date.now().toString(36).toUpperCase()}-${Math.random().toString(36).substring(2, 6).toUpperCase()}`;
}

// Create a new empty application
export function createNewApplication(method: OnboardingMethod): Application {
  const now = new Date().toISOString();
  return {
    application_id: generateApplicationId(),
    status: "DRAFT",
    onboarding_method: method,
    created_at: now,
    updated_at: now,
    current_step: 1,
    completed_steps: [],
    upload_mode: "BULK",
    business_profile: {},
    addresses: [],
    business_contacts: [],
    business_activity: {},
    transfer_behavior: {},
    ownership_structure: {},
    directors: [],
    signatories: [],
    ubos: [],
    documents: [],
    field_provenance: {},
    submission_confirmations: {
      confirm_accuracy: false,
      confirm_authority: false,
    },
    ops_notes: [],
  };
}

// Get all applications from localStorage
export function getAllApplications(): Application[] {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    return stored ? JSON.parse(stored) : [];
  } catch {
    return [];
  }
}

// Get a single application by ID
export function getApplicationById(applicationId: string): Application | null {
  const apps = getAllApplications();
  return apps.find((app) => app.application_id === applicationId) || null;
}

// Save application to localStorage
export function saveApplication(application: Application): void {
  const apps = getAllApplications();
  const index = apps.findIndex((app) => app.application_id === application.application_id);

  const updatedApp = {
    ...application,
    updated_at: new Date().toISOString(),
  };

  if (index >= 0) {
    apps[index] = updatedApp;
  } else {
    apps.push(updatedApp);
  }

  localStorage.setItem(STORAGE_KEY, JSON.stringify(apps));
}
