// CopilotKit runtime URL resolver.
//
// Two modes match how the editor (atomic-fi-jdm-editor) does it:
//   - Vite dev mode: /api/copilotkit is proxied to http://localhost:4242
//     by vite.config.ts. Use the default.
//   - Phoenix-served prod: same-origin /api/copilotkit gets forwarded by
//     Phoenix to the copilot-runtime sidecar (when that proxy is wired).
//   - Custom host: set VITE_COPILOT_RUNTIME_URL to an absolute URL.
//
// The runtime lives at external-deps/copilot-runtime/ in this monorepo.
// Default LLM provider is Ollama qwen3.5:9b (see docker.env there).

export function copilotRuntimeUrl(): string {
  const override = import.meta.env.VITE_COPILOT_RUNTIME_URL as string | undefined;
  return override?.trim() || "/api/copilotkit";
}
