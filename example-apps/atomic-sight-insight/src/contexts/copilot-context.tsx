import { createContext, useCallback, useContext, useMemo, useRef, useState, type ReactNode } from "react";
import type { TransactionResponse } from "@/api/types";
import { resolveNlQuery, type CopilotResolution, type CopilotToolStep } from "@/lib/nlQuery";

type StreamedStep = CopilotToolStep & { state: "running" | "done" };

type CopilotContextValue = {
  open: boolean;
  prompt: string;
  steps: StreamedStep[];
  resolution: CopilotResolution | null;
  isRunning: boolean;
  appliedRows: TransactionResponse[] | null;
  openDrawer: () => void;
  closeDrawer: () => void;
  setPrompt: (s: string) => void;
  run: (prompt?: string) => Promise<void>;
  applyToView: () => void;
  clearApplied: () => void;
};

const CopilotContext = createContext<CopilotContextValue | null>(null);

export function CopilotProvider({ children }: { children: ReactNode }) {
  const [open, setOpen] = useState(false);
  const [prompt, setPrompt] = useState("");
  const [steps, setSteps] = useState<StreamedStep[]>([]);
  const [resolution, setResolution] = useState<CopilotResolution | null>(null);
  const [isRunning, setIsRunning] = useState(false);
  const [appliedRows, setAppliedRows] = useState<TransactionResponse[] | null>(null);
  const cancelRef = useRef(false);

  const openDrawer = useCallback(() => setOpen(true), []);
  const closeDrawer = useCallback(() => setOpen(false), []);

  const run = useCallback(async (override?: string) => {
    const q = (override ?? prompt).trim();
    if (!q) return;
    cancelRef.current = false;
    setIsRunning(true);
    setResolution(null);
    setSteps([]);
    const res = resolveNlQuery(q);
    for (let i = 0; i < res.steps.length; i++) {
      if (cancelRef.current) break;
      // push as running
      setSteps((prev) => [...prev, { ...res.steps[i], state: "running" }]);
      // simulate latency
      await new Promise((r) => setTimeout(r, 380 + Math.random() * 220));
      setSteps((prev) => prev.map((s, idx) => (idx === i ? { ...s, state: "done" } : s)));
    }
    setResolution(res);
    setIsRunning(false);
  }, [prompt]);

  const applyToView = useCallback(() => {
    if (resolution) setAppliedRows(resolution.txRows);
  }, [resolution]);

  const clearApplied = useCallback(() => setAppliedRows(null), []);

  const value = useMemo<CopilotContextValue>(() => ({
    open, prompt, steps, resolution, isRunning, appliedRows,
    openDrawer, closeDrawer, setPrompt, run, applyToView, clearApplied,
  }), [open, prompt, steps, resolution, isRunning, appliedRows, openDrawer, closeDrawer, run, applyToView, clearApplied]);

  return <CopilotContext.Provider value={value}>{children}</CopilotContext.Provider>;
}

export function useCopilot() {
  const ctx = useContext(CopilotContext);
  if (!ctx) throw new Error("useCopilot must be used within CopilotProvider");
  return ctx;
}
