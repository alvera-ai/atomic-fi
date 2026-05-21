import { expect, type Page } from "@playwright/test";

// The onboarding app gates on an API key entered at the ConnectGate.
// Test harnesses are allowed env config — default to dev.exs's
// `root_api_key` so the suite runs against a stock `make server`.
export const API_KEY = process.env.ONBOARDING_API_KEY ?? "alvera_root_api_key_dev";

/** Pass the startup ConnectGate, then wait for the gated app to render. */
export async function connectGate(page: Page) {
  const apiKeyInput = page.locator("#api-key");
  await apiKeyInput.waitFor({ timeout: 10_000 });
  await apiKeyInput.fill(API_KEY);
  await page.locator("button", { hasText: "Connect" }).click();
  // The gate unmounts once the key verifies and the app routes render.
  await expect(apiKeyInput).toBeHidden({ timeout: 10_000 });
}
