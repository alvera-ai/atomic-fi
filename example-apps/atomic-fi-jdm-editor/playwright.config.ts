import { defineConfig } from "@playwright/test";

// The atomic-fi-jdm-editor demo is served by Phoenix under
// /demo/atomic-fi-jdm-editor/ (the Vite `base`), not a standalone dev
// server. `make server` builds it (a Vite watcher) and serves it via
// Plug.Static + the SPA-fallback route.
//
// Run with `make server` already up AND `ollama serve` running (the
// copilot spec drives a live local model):
//   pnpm --filter atomic-fi-jdm-editor exec playwright test
//
// baseURL ends in a slash so specs use relative gotos
// (`page.goto("rules/onboarding")`). The app's React Router has
// basename "/demo/atomic-fi-jdm-editor/", so those resolve client-side.
//
// timeout is generous: a copilot turn drives qwen3.5:9b (a local
// thinking model) and runs for minutes — §2 raises it further still.
export default defineConfig({
  testDir: "./e2e",
  timeout: 600_000,
  retries: 0,
  use: {
    baseURL: "http://localhost:4100/demo/atomic-fi-jdm-editor/",
    headless: true,
    screenshot: "only-on-failure",
  },
});
