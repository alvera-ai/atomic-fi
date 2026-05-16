import { useState, useEffect, useCallback } from 'react';
import { Application, ApplicationStatus, OnboardingMethod } from '@/types/onboarding';

const STORAGE_KEY = 'fintech_applications';

// Generate a random application ID
export function generateApplicationId(): string {
  return `APP-${Date.now().toString(36).toUpperCase()}-${Math.random().toString(36).substring(2, 6).toUpperCase()}`;
}

// Create a new empty application
export function createNewApplication(method: OnboardingMethod): Application {
  const now = new Date().toISOString();
  return {
    application_id: generateApplicationId(),
    status: 'DRAFT',
    onboarding_method: method,
    created_at: now,
    updated_at: now,
    current_step: 1,
    completed_steps: [],
    upload_mode: 'BULK',
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
  return apps.find(app => app.application_id === applicationId) || null;
}

// Save application to localStorage
export function saveApplication(application: Application): void {
  const apps = getAllApplications();
  const index = apps.findIndex(app => app.application_id === application.application_id);
  
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

// Delete application from localStorage
export function deleteApplication(applicationId: string): void {
  const apps = getAllApplications();
  const filtered = apps.filter(app => app.application_id !== applicationId);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(filtered));
}

// Custom hook for managing a single application
export function useApplication(applicationId: string | undefined) {
  const [application, setApplication] = useState<Application | null>(null);
  const [loading, setLoading] = useState(true);
  const [lastSaved, setLastSaved] = useState<Date | null>(null);

  // Load application on mount
  useEffect(() => {
    if (applicationId) {
      const app = getApplicationById(applicationId);
      setApplication(app);
    }
    setLoading(false);
  }, [applicationId]);

  // Update and autosave
  const updateApplication = useCallback((updates: Partial<Application>) => {
    if (!application) return;
    
    const updatedApp = {
      ...application,
      ...updates,
    };
    
    setApplication(updatedApp);
    saveApplication(updatedApp);
    setLastSaved(new Date());
  }, [application]);

  // Update nested data with autosave
  const updateField = useCallback(<K extends keyof Application>(
    field: K,
    value: Application[K]
  ) => {
    if (!application) return;
    
    const updatedApp = {
      ...application,
      [field]: value,
    };
    
    setApplication(updatedApp);
    saveApplication(updatedApp);
    setLastSaved(new Date());
  }, [application]);

  // Mark step as complete
  const completeStep = useCallback((stepId: number) => {
    if (!application) return;
    
    const completedSteps = application.completed_steps.includes(stepId)
      ? application.completed_steps
      : [...application.completed_steps, stepId];
    
    updateApplication({ completed_steps: completedSteps });
  }, [application, updateApplication]);

  // Set current step
  const setCurrentStep = useCallback((stepId: number) => {
    updateApplication({ current_step: stepId });
  }, [updateApplication]);

  // Update status
  const updateStatus = useCallback((status: ApplicationStatus) => {
    updateApplication({ status });
  }, [updateApplication]);

  return {
    application,
    loading,
    lastSaved,
    updateApplication,
    updateField,
    completeStep,
    setCurrentStep,
    updateStatus,
  };
}

// Custom hook for applications list (ops view)
export function useApplicationsList() {
  const [applications, setApplications] = useState<Application[]>([]);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(() => {
    setApplications(getAllApplications());
    setLoading(false);
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  return { applications, loading, refresh };
}
