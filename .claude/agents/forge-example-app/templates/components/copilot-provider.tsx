import { type ReactNode } from "react";
import { CopilotKit } from "@copilotkit/react-core";
import { copilotRuntimeUrl } from "@/lib/copilot";

// Wraps the app with a CopilotKit context so the JDM editor (and any
// other consumer) can register tools / chat. The runtime URL resolves to
// either /api/copilotkit (proxied by vite dev or by Phoenix in prod) or
// VITE_COPILOT_RUNTIME_URL if explicitly set.
//
// agentName="default" matches the runtime's default agent name; if you
// run multiple agents in copilot-runtime, change accordingly.
export function CopilotProvider({ children }: { children: ReactNode }) {
  return (
    <CopilotKit runtimeUrl={copilotRuntimeUrl()} agent="default">
      {children}
    </CopilotKit>
  );
}
