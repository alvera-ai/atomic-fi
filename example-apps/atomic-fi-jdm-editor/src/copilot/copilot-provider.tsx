import React from 'react';
import { CopilotKit } from '@copilotkit/react-core';
import '@copilotkit/react-ui/styles.css';

export const CopilotProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  return (
    <CopilotKit
      runtimeUrl="/api/copilotkit"
      // No agent id — we use the default chat-completion flow with the sidecar's system prompt.
    >
      {children}
    </CopilotKit>
  );
};
