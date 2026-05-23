/// <reference types="vite/client" />

declare global {
  interface Window {
    /**
     * E2E test hook — a deterministic summary of the open decision
     * graph, refreshed on every change (see pages/decision-simple.tsx).
     * Playwright asserts against this instead of polling the React Flow
     * canvas, which has no stable per-node DOM.
     */
    __jdmEditor?: {
      nodeCount: number;
      nodeNames: string[];
      edgeCount: number;
      dirty: boolean;
    };
  }
}

export {};
