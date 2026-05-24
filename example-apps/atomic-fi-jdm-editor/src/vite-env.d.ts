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
    /**
     * Monaco editor's library global, installed by @gorules/jdm-editor
     * when the simulator panel mounts. E2E specs reach for the
     * Request / Output editors directly — `getEditors()[0]` is the
     * Request input, `[1]` is the Output. Loose typing here is
     * deliberate: the spec only needs `setValue` / `getValue` and we
     * don't want to drag in the full monaco type package.
     */
    monaco?: {
      editor: {
        getEditors: () => Array<{
          setValue: (value: string) => void;
          getValue: () => string;
        }>;
        getModels: () => Array<{
          getValue: () => string;
          setValue: (value: string) => void;
        }>;
      };
    };
  }
}

export {};
