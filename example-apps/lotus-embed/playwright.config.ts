import { defineConfig } from "@playwright/test";

// The lotus-embed demo is served by Phoenix under /demo/lotus-embed/ (the
// Vite `base`), not by a standalone dev server. `make server` builds it
// (a Vite watcher) and serves it via Plug.Static + the SPA-fallback route.
//
// Run the suite with `make server` already up:
//   pnpm --filter lotus-embed exec playwright test
//
// lotus-embed has no client-side router — baseURL is just the app root.
export default defineConfig({
  testDir: "./e2e",
  timeout: 60_000,
  retries: 0,
  use: {
    baseURL: "http://localhost:4100/demo/lotus-embed/",
    headless: true,
    screenshot: "only-on-failure",
  },
});
