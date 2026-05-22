import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "@playwright/test";
import { connectGate } from "./connect";

const here = dirname(fileURLToPath(import.meta.url));
const credsPath = resolve(here, "../../../priv/repo/.bootstrap_creds.json");

type BootstrapCreds = {
  tenantSlug: string;
  adminEmail: string;
  adminPassword: string;
  rootApiKey: string;
  platformAdminApiKey: string;
};

const API_BASE = "http://localhost:4100";
const HAS_BACKEND_CREDS = existsSync(credsPath);

function loadCreds(): BootstrapCreds {
  return JSON.parse(readFileSync(credsPath, "utf8"));
}

async function postSession(creds: BootstrapCreds) {
  const res = await fetch(`${API_BASE}/api/sessions`, {
    method: "POST",
    headers: { "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify({
      email: creds.adminEmail,
      password: creds.adminPassword,
      tenant_slug: creds.tenantSlug,
      expires_in: 3600,
    }),
  });
  if (!res.ok) throw new Error(`Session POST → ${res.status}: ${await res.text()}`);
  const body = (await res.json()) as { bearer: string; tenant: { id: string } };
  return { bearer: body.bearer, tenantId: body.tenant.id };
}

function authHeaders(bearer: string) {
  return {
    "content-type": "application/json",
    accept: "application/json",
    authorization: `Bearer ${bearer}`,
  };
}

async function safeDelete(path: string, bearer: string) {
  await fetch(`${API_BASE}${path}`, {
    method: "DELETE",
    headers: authHeaders(bearer),
  }).catch(() => undefined);
}

test.describe("M1 Onboarding — AccountHolder end-to-end", () => {
  let bearer: string;
  let tenantId: string;
  let createdAccountHolderId: string | undefined;

  test.beforeAll(async () => {
    if (!HAS_BACKEND_CREDS) return;
    const creds = loadCreds();
    const session = await postSession(creds);
    bearer = session.bearer;
    tenantId = session.tenantId;
  });

  test.afterAll(async () => {
    if (createdAccountHolderId && bearer) {
      await safeDelete(`/api/account-holders/${createdAccountHolderId}`, bearer);
    }
  });

  test("fill onboarding form and submit", async ({ page }) => {
    // 1. Navigate to start page
    await page.goto("start");
    await connectGate(page);
    await expect(page.locator("h1", { hasText: "Start your application" })).toBeVisible({
      timeout: 10_000,
    });

    // 2. Select "Manual entry" card and click "Start Application"
    await page.locator("text=Manual entry").click();
    await page.locator("button", { hasText: "Start Application" }).click();

    // 3. Wait for navigation to documents step
    await page.waitForURL(/\/onboarding\/.*\/documents/, { timeout: 10_000 });
    const applicationId = page.url().match(/\/onboarding\/([^/]+)/)?.[1] ?? "";
    expect(applicationId).toBeTruthy();

    // 4. Navigate to identity step and fill business profile
    await page.goto(`onboarding/${applicationId}/identity`);
    await expect(page.locator("h1", { hasText: "Business identity" })).toBeVisible();

    await page.locator("#legal_name").fill("E2E Test Corp LLC");
    await page.locator("#trade_name").fill("E2E Trading");
    await page.locator("#license_number").fill("E2E-12345");
    await page.locator("#license_expiry").fill("2026-12-31");
    await page.locator("#incorporation_date").fill("2023-01-15");

    // Select jurisdiction via the trigger button
    await page.getByRole("combobox").first().click();
    await page.getByRole("option", { name: "Dubai Mainland" }).click();

    // Select entity type via the trigger button
    await page.getByRole("combobox").nth(1).click();
    await page.getByRole("option", { name: /Limited Liability Company/ }).click();

    // Wait for autosave
    await page.waitForTimeout(500);

    // 5. Seed remaining data in localStorage (steps that don't need UI testing)
    await page.evaluate(
      ({ appId, tid }) => {
        const key = "fintech_applications";
        const stored = localStorage.getItem(key);
        const apps = stored ? JSON.parse(stored) : [];
        const idx = apps.findIndex((a: { application_id: string }) => a.application_id === appId);
        if (idx < 0) return;

        apps[idx] = {
          ...apps[idx],
          addresses: [
            {
              id: "addr-1",
              type: "REGISTERED",
              line1: "123 Test Street",
              city: "Dubai",
              emirate: "Dubai",
              country: "AE",
              postal_code: "00000",
            },
          ],
          directors: [
            {
              id: "dir-1",
              full_name: "John Director",
              nationality: "US",
              date_of_birth: "1985-06-15",
              passport_number: "P123456789",
              email: "john@e2etest.com",
              phone: "+971501234567",
              is_signatory: true,
            },
          ],
          ubos: [
            {
              id: "ubo-1",
              full_name: "Jane Owner",
              nationality: "US",
              date_of_birth: "1980-03-20",
              ownership_percentage: 100,
              passport_number: "P987654321",
              residential_address: "456 Owner Ave, New York, US",
            },
          ],
          completed_steps: [1, 2, 3, 4, 5, 6, 7, 8, 9],
          submission_confirmations: {
            confirm_accuracy: true,
            confirm_authority: true,
          },
          _tenant_id: tid,
        };
        localStorage.setItem(key, JSON.stringify(apps));
      },
      { appId: applicationId, tid: tenantId ?? "" },
    );

    // 6. Navigate to review step
    await page.goto(`onboarding/${applicationId}/review`);
    await expect(page.locator("h1", { hasText: "Review & submit" })).toBeVisible();

    // 7. Verify all steps show as complete
    const incompleteCount = await page.locator("text=Incomplete").count();
    expect(incompleteCount).toBe(0);

    // 8. Submit
    const submitButton = page.locator("button", { hasText: "Submit Application" });
    await expect(submitButton).toBeEnabled();
    await submitButton.click();

    // 9. Wait for navigation to status page
    await page.waitForURL(/\/status\//, { timeout: 30_000 });
    await expect(page).toHaveURL(/\/status\//);

    // 10. Backend verification (only when backend is available)
    if (!HAS_BACKEND_CREDS || !bearer) return;

    const ahRes = await fetch(
      `${API_BASE}/api/account-holders?page_size=5&order_by=inserted_at&order_directions=desc`,
      { headers: authHeaders(bearer) },
    );
    expect(ahRes.ok).toBe(true);
    const ahBody = (await ahRes.json()) as {
      data: Array<{
        id: string;
        account_holder_type: string;
        legal_entity: { id: string; business_name: string };
      }>;
    };
    const created = ahBody.data.find((ah) => ah.account_holder_type === "business");
    expect(created).toBeTruthy();
    createdAccountHolderId = created?.id;

    // The AccountHolder response embeds the full LegalEntity — there is no
    // standalone GET /api/legal-entities/:id endpoint.
    expect(created?.legal_entity.business_name).toBe("E2E Test Corp LLC");
  });
});
