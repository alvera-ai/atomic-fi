import React, { useState } from 'react';
import { createBrowserRouter, Navigate, RouterProvider } from 'react-router-dom';
import { DecisionSimplePage } from './pages/decision-simple.tsx';
import { NotFoundPage } from './pages/not-found';
import { RulesIndexPage } from './pages/rules-index.tsx';
import { CopilotProvider } from './copilot/copilot-provider';
import { ConnectGate } from './features/connect/connect-gate';
import { getStoredApiKey } from './features/connect/api-key';

const router = createBrowserRouter(
  [
    {
      path: '/',
      element: <Navigate to="/rules/onboarding" replace />,
    },
    {
      path: '/rules/:ruleType',
      element: <RulesIndexPage />,
    },
    {
      path: '/rules/:ruleType/:name',
      element: (
        <CopilotProvider>
          <DecisionSimplePage />
        </CopilotProvider>
      ),
    },
    {
      path: '*',
      element: <NotFoundPage />,
    },
  ],
  // basename = the Vite `base` ("/demo/atomic-fi-jdm-editor/" here, "/"
  // for a standalone `pnpm dev`). Phoenix serves the app under that
  // prefix via Plug.Static, so the router strips it before matching.
  { basename: import.meta.env.BASE_URL },
);

// The editor ships no credentials. ConnectGate collects a backend API
// key (verified against GET /api/sessions/verify) and holds it in
// sessionStorage for the tab; the gated app renders only once a key is
// present. A key kept earlier this session lets the user straight
// through and survives reloads.
export const App: React.FC = () => {
  const [connected, setConnected] = useState(() => getStoredApiKey() !== null);

  if (!connected) {
    return <ConnectGate onConnected={() => setConnected(true)} />;
  }

  return <RouterProvider router={router} />;
};
