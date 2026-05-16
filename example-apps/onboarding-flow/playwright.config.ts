import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  timeout: 60_000,
  retries: 0,
  use: {
    baseURL: "http://localhost:8080",
    headless: true,
    screenshot: "only-on-failure",
  },
  webServer: {
    command: "pnpm dev",
    port: 8080,
    reuseExistingServer: true,
    timeout: 30_000,
  },
});
