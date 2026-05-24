import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "@playwright/test";
import { connectGate } from "./connect";

const here = dirname(fileURLToPath(import.meta.url));
const MOA_PATH = resolve(
  here,
  "../../../../document-processing/Memorandum_Association-compressed.pdf",
);
const BANK_PATH = resolve(here, "../../../../document-processing/UAE_Bank_Statement_Feb2025.pdf");

const HAS_DOCS = existsSync(MOA_PATH) && existsSync(BANK_PATH);

test.describe("AI Document Extraction", () => {
  test.skip(!HAS_DOCS, "Sample PDFs not available at ../document-processing/");

  test("upload documents and AI-extract to prefill form", async ({ page }) => {
    await page.goto("start");
    await connectGate(page);
    await expect(page.locator("h1", { hasText: "Start your application" })).toBeVisible({
      timeout: 10_000,
    });

    await page.locator("text=Manual entry").click();
    await page.locator("button", { hasText: "Start Application" }).click();
    await page.waitForURL(/\/onboarding\/.*\/documents/, { timeout: 10_000 });

    const fileInput = page.locator('input[type="file"]');
    await fileInput.setInputFiles([MOA_PATH, BANK_PATH]);
    await expect(page.locator("text=2 file")).toBeVisible({ timeout: 5_000 });

    await page.locator("button", { hasText: "Process files" }).click();
    await expect(page.locator("text=document(s) processed")).toBeVisible({ timeout: 60_000 });

    const applicationId = page.url().match(/\/onboarding\/([^/]+)/)?.[1] ?? "";

    // Business identity prefilled from MOA
    await page.goto(`onboarding/${applicationId}/identity`);
    await expect(page.locator("#legal_name")).toHaveValue(/GULF PHARMACEUTICAL/i, {
      timeout: 5_000,
    });

    // Directors prefilled from MOA
    await page.goto(`onboarding/${applicationId}/directors`);
    await expect(page.locator("main").locator("text=Sheikh Saud").first()).toBeVisible({
      timeout: 5_000,
    });

    // UBOs prefilled from MOA shareholders
    await page.goto(`onboarding/${applicationId}/ubos`);
    await expect(page.locator("main").locator("text=Ras Al Khaimah")).toBeVisible({
      timeout: 5_000,
    });
  });
});
