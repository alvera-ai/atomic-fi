import React from 'react';
import { message } from 'antd';
import { CopilotKitProvider } from '@copilotkit/react-core/v2';
import '@copilotkit/react-core/v2/styles.css';

// The copilot session root. `runtimeUrl` points at the copilot-runtime
// sidecar that brokers LLM calls (docs/copilot-architecture.md §8,
// docs/adr/ADR-002). It is env-driven so the editor can target the
// standalone sidecar without a code change; unset, it falls back to the
// same-origin /api/copilotkit path.
const runtimeUrl = (import.meta.env.VITE_COPILOT_RUNTIME_URL as string | undefined) ?? '/api/copilotkit';

// `<CopilotKitProvider onError>` receives every error CopilotKit's client
// surfaces — RUN_ERROR AG-UI events from the runtime, transcription
// failures, transport-level failures. We forward them to Ant Design's
// `message` API so the user sees what happened instead of staring at a
// frozen chat. The runtime auto-emits RUN_ERROR when the BuiltInAgent's
// factory or the AI SDK stream throws — see
// `@copilotkit/runtime/dist/agent/index.mjs` (the `subscriber.next(
// runErrorEvent)` branches).
const handleCopilotError = (event: unknown): void => {
  // CopilotKit's error events are not JSON-safe (they carry the live
  // observable subscriber as a circular reference). Probe known string
  // fields in order of preference; fall back to a generic label rather
  // than serialising — JSON.stringify(event) throws on the cycle.
  const e = event as { message?: string; error?: { message?: string }; code?: string };
  const detail =
    (typeof event === 'string' && event) ||
    e?.message ||
    e?.error?.message ||
    e?.code ||
    'unknown copilot error';
  message.error(`Copilot error: ${detail}`, 8);
};

export const CopilotProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  // `showDevConsole="auto"` floats the CopilotKitInspector — the same widget
  // CopilotKit's own examples/v2/react/demo uses — so the live agent /
  // message-store state is visible while we debug v2 parity against v1.
  return (
    <CopilotKitProvider runtimeUrl={runtimeUrl} showDevConsole="auto" onError={handleCopilotError}>
      {children}
    </CopilotKitProvider>
  );
};
