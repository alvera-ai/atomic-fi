import { expect, type Page } from "@playwright/test";

// The JDM editor gates on a backend API key entered at the ConnectGate
// and verified against GET /api/sessions/verify. Test harnesses are
// allowed env config — default to dev.exs's root_api_key so the suite
// runs against a stock `make server`.
export const API_KEY = process.env.JDM_EDITOR_API_KEY ?? "alvera_root_api_key_dev";

/** Pass the startup ConnectGate, then wait for the gated app to render. */
export async function connectGate(page: Page): Promise<void> {
  const apiKeyInput = page.locator("#api-key");
  await apiKeyInput.waitFor({ timeout: 15_000 });
  await apiKeyInput.fill(API_KEY);
  await page.locator("#connect-button").click();
  // The gate unmounts once the key verifies and the router renders.
  await expect(apiKeyInput).toBeHidden({ timeout: 15_000 });
}
