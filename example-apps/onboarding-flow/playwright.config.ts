import { defineConfig } from "@playwright/test";

// The onboarding-flow demo is served by Phoenix under /demo/onboarding-flow/
// (the Vite `base`), not by a standalone dev server. `make server` builds it
// (a Vite watcher) and serves it via Plug.Static + the SPA-fallback route.
//
// Run the suite with `make server` already up:
//   pnpm --filter onboarding-flow exec playwright test
//
// baseURL ends in a slash so specs use relative gotos
// (`page.goto("start")` → /demo/onboarding-flow/start). The app's React
// Router has basename "/demo/onboarding-flow/", so those resolve to the
// "/start" route client-side.
export default defineConfig({
  testDir: "./e2e",
  timeout: 60_000,
  retries: 0,
  use: {
    baseURL: "http://localhost:4100/demo/onboarding-flow/",
    headless: true,
    screenshot: "only-on-failure",
  },
});
