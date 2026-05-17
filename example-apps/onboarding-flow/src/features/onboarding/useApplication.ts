import { useCallback, useEffect, useState } from "react";
import { getAllApplications, getApplicationById, saveApplication } from "./store";
import type { Application, ApplicationStatus } from "./types";

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
  const updateApplication = useCallback(
    (updates: Partial<Application>) => {
      if (!application) return;

      const updatedApp = {
        ...application,
        ...updates,
      };

      setApplication(updatedApp);
      saveApplication(updatedApp);
      setLastSaved(new Date());
    },
    [application],
  );

  // Update nested data with autosave
  const updateField = useCallback(
    <K extends keyof Application>(field: K, value: Application[K]) => {
      if (!application) return;

      const updatedApp = {
        ...application,
        [field]: value,
      };

      setApplication(updatedApp);
      saveApplication(updatedApp);
      setLastSaved(new Date());
    },
    [application],
  );

  // Mark step as complete
  const completeStep = useCallback(
    (stepId: number) => {
      if (!application) return;

      const completedSteps = application.completed_steps.includes(stepId)
        ? application.completed_steps
        : [...application.completed_steps, stepId];

      updateApplication({ completed_steps: completedSteps });
    },
    [application, updateApplication],
  );

  // Set current step
  const setCurrentStep = useCallback(
    (stepId: number) => {
      updateApplication({ current_step: stepId });
    },
    [updateApplication],
  );

  // Update status
  const updateStatus = useCallback(
    (status: ApplicationStatus) => {
      updateApplication({ status });
    },
    [updateApplication],
  );

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
