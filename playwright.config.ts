import { defineConfig } from "@playwright/test";

// Root Playwright config — one project per demo app, all served by
// Phoenix under `/demo/<app>/` (Plug.Static + SPA-fallback). Prereqs:
//
//   make run-backing-services   ZenRule :8090, Watchman :8084, copilot-runtime :4242
//   make server                 Phoenix :4100 + per-app vite build --watch
//   ollama serve                :11434 (qwen3.5:9b for the JDM copilot)
//
// Run the whole suite from the repo root:
//   pnpm e2e             all projects
//   pnpm e2e:jdm         only the JDM editor
//   pnpm e2e:onboarding  only onboarding-flow
//   pnpm e2e:lotus       only lotus-embed
//
// Headed by default — the JDM copilot turns drive a live local Ollama
// for minutes per turn, and a visible browser is the only sensible way
// to watch a run. Per-spec `test.use({ headless: true })` is still
// available if a future smoke spec wants to opt out.
//
// Timeout is the most permissive (JDM copilot's 600s budget); shorter
// projects ignore the headroom.
export default defineConfig({
  timeout: 600_000,
  retries: 0,
  reporter: [["list"], ["html", { outputFolder: "playwright-report", open: "never" }]],
  outputDir: "test-results",
  // Warm Ollama before the suite — `qwen3.5:9b` auto-unloads after 5
  // minutes of idle; cold-loading it costs the first JDM-project test
  // its whole 540 s per-turn budget. The setup script is a no-op when
  // Ollama isn't reachable (it logs and continues), so the onboarding
  // and lotus-embed projects don't pay for it.
  globalSetup: "./playwright.global-setup.ts",
  use: {
    headless: false,
    screenshot: "only-on-failure",
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "onboarding-flow",
      testDir: "./example-apps/onboarding-flow/e2e",
      use: { baseURL: "http://localhost:4100/demo/onboarding-flow/" },
    },
    {
      name: "lotus-embed",
      testDir: "./example-apps/lotus-embed/e2e",
      use: { baseURL: "http://localhost:4100/demo/lotus-embed/" },
    },
    {
      name: "atomic-fi-jdm-editor",
      testDir: "./example-apps/atomic-fi-jdm-editor/e2e",
      use: { baseURL: "http://localhost:4100/demo/atomic-fi-jdm-editor/" },
    },
  ],
});
