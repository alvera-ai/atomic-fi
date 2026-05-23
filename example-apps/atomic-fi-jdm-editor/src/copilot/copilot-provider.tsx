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
  // Gate the CopilotKitInspector on Vite's build mode rather than its
  // "auto" heuristic. Two reasons:
  //   1. UX — the demo bundle that ships to `/demo/atomic-fi-jdm-editor/`
  //      is built with `vite build --watch` (production mode), so end
  //      users would otherwise see the inspector widget. It's a debug
  //      tool, not a feature.
  //   2. E2E — the inspector is `position: fixed` at the top-right
  //      corner with `z-index: 2147483646` (max), and overlaps the
  //      `#copilot-toggle` button at its 1-pixel edge. Playwright treats
  //      the overlap as a pointer-event interception and refuses to
  //      click. Hiding it in the built bundle removes both problems in
  //      one change; local `pnpm dev` keeps the inspector via
  //      `import.meta.env.DEV`.
  const showDevConsole = import.meta.env.DEV;
  return (
    <CopilotKitProvider runtimeUrl={runtimeUrl} showDevConsole={showDevConsole} onError={handleCopilotError}>
      {children}
    </CopilotKitProvider>
  );
};
