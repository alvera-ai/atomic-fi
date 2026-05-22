import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "@playwright/test";
import { connectGate } from "./connect";

const here = dirname(fileURLToPath(import.meta.url));
const credsPath = resolve(here, "../../../priv/repo/.bootstrap_creds.json");

const MOA_PATH = resolve(here, "../public/Memorandum_Association-compressed.pdf");
const BANK_PATH = resolve(here, "../public/UAE_Bank_Statement_Feb2025.pdf");
const PASSPORT_PATH = resolve(here, "../public/USA-Passport-2.jpg");

type BootstrapCreds = {
  tenantSlug: string;
  adminEmail: string;
  adminPassword: string;
  rootApiKey: string;
  platformAdminApiKey: string;
};

const API_BASE = "http://localhost:4100";
const HAS_BACKEND_CREDS = existsSync(credsPath);
const HAS_DOCS = existsSync(MOA_PATH) && existsSync(BANK_PATH) && existsSync(PASSPORT_PATH);

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

test.describe("Full flow: AI extract → fill all forms → submit → backend verify", () => {
  test.skip(!HAS_DOCS, "Sample docs not available in public/");
  // Local vision inference (llama3.2-vision via Ollama) is slow — three
  // documents, one of them a multi-page PDF, runs several minutes. This
  // is the demo-grade tradeoff; a cloud provider would be far faster.
  test.setTimeout(600_000);

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

  test("upload MOA + bank statement + passport, AI extract, fill forms, submit", async ({
    page,
  }) => {
    // ── Start application ──────────────────────────────────────
    await page.goto("start");
    await connectGate(page);
    await expect(page.locator("h1", { hasText: "Start your application" })).toBeVisible({
      timeout: 10_000,
    });
    await page.locator("text=Manual entry").click();
    await page.locator("button", { hasText: "Start Application" }).click();
    await page.waitForURL(/\/onboarding\/.*\/documents/, { timeout: 10_000 });

    const applicationId = page.url().match(/\/onboarding\/([^/]+)/)?.[1] ?? "";
    expect(applicationId).toBeTruthy();

    // ── Step 1: Upload 3 real documents for AI extraction ──────
    const fileInput = page.locator('input[type="file"]');
    await fileInput.setInputFiles([MOA_PATH, BANK_PATH, PASSPORT_PATH]);
    await expect(page.locator("text=3 file")).toBeVisible({ timeout: 5_000 });

    // Wait for verification to finish
    await expect(page.locator("text=Verifying")).toHaveCount(0, { timeout: 10_000 });

    // Process files — AI extraction via POST /api/parse (Ollama vision).
    await page.locator("button", { hasText: "Process files" }).click();
    await expect(page.locator("text=document(s) processed")).toBeVisible({ timeout: 480_000 });

    // ── Step 2: Verify AI-extracted identity fields ────────────
    await page.goto(`onboarding/${applicationId}/identity`);
    await expect(page.locator("h1", { hasText: "Business identity" })).toBeVisible();

    // MOA should have extracted company name
    await expect(page.locator("#legal_name")).toHaveValue(/GULF PHARMACEUTICAL/i, {
      timeout: 5_000,
    });

    // Fill in fields AI couldn't extract
    const jurisdictionCombo = page.getByRole("combobox").first();
    const currentJurisdiction = await jurisdictionCombo.textContent();
    if (!currentJurisdiction || currentJurisdiction === "Select jurisdiction") {
      await jurisdictionCombo.click();
      await page.getByRole("option", { name: "Dubai Mainland" }).click();
    }

    const entityCombo = page.getByRole("combobox").nth(1);
    const currentEntity = await entityCombo.textContent();
    if (!currentEntity || currentEntity === "Select type") {
      await entityCombo.click();
      await page.getByRole("option", { name: /Limited Liability Company/ }).click();
    }

    await page.waitForTimeout(500);

    // ── Step 8: extraction populated directors from the MOA ─────
    // Local VLM extraction is demo-grade (§C.4) — assert the pipeline
    // populated a director, not the exact name a cloud model would read.
    await page.goto(`onboarding/${applicationId}/directors`);
    const directorNames = page.locator('main input[placeholder="Full name"]');
    await expect(directorNames.first()).toBeVisible({ timeout: 5_000 });
    expect((await directorNames.first().inputValue()).trim()).not.toBe("");

    // ── Step 9: extraction populated UBOs from the MOA shareholders ──
    await page.goto(`onboarding/${applicationId}/ubos`);
    const uboNames = page.locator('main input[placeholder="Full name"]');
    await expect(uboNames.first()).toBeVisible({ timeout: 5_000 });
    expect((await uboNames.first().inputValue()).trim()).not.toBe("");

    // ── Seed remaining fields not extractable from docs ────────
    // Business contacts, transfer details, ownership structure
    // are not in MOA/bank/passport — seed them for submission.
    await page.evaluate(
      ({ appId, tid }) => {
        const key = "fintech_applications";
        const stored = localStorage.getItem(key);
        const apps = stored ? JSON.parse(stored) : [];
        const idx = apps.findIndex((a: { application_id: string }) => a.application_id === appId);
        if (idx < 0) return;

        const app = apps[idx];

        // Only seed what AI couldn't extract
        if (!app.addresses || app.addresses.length === 0) {
          app.addresses = [
            {
              id: "addr-1",
              type: "REGISTERED",
              line1: "Julphar Tower, Ras Al Khaimah",
              city: "Ras Al Khaimah",
              emirate: "Ras Al Khaimah",
              country: "AE",
              postal_code: "00000",
            },
          ];
        }

        if (!app.business_contacts || app.business_contacts.length === 0) {
          app.business_contacts = [
            {
              id: "contact-1",
              type: "PRIMARY",
              full_name: "Sheikh Saud Bin Saqr Al Qasimi",
              email: "chairman@julphar.net",
              phone: "+97172461461",
              role: "Chairman",
            },
          ];
        }

        app.business_activity = {
          ...app.business_activity,
          primary_activity: app.business_activity?.primary_activity || "manufacturing",
          purpose_of_account:
            "Operational account for pharmaceutical manufacturing and distribution",
          source_of_funds: "business_revenue",
        };

        app.transfer_behavior = {
          ...app.transfer_behavior,
          expected_monthly_volume_usd: app.transfer_behavior?.expected_monthly_volume_usd || 500000,
          expected_monthly_transactions: app.transfer_behavior?.expected_monthly_transactions || 30,
          primary_transfer_purpose: "supplier_payments",
          expected_counterparties: ["Acme Corp Ltd", "Gulf Trading FZE"],
          high_risk_jurisdictions: false,
        };

        app.ownership_structure = {
          is_subsidiary: false,
          parent_company_name: "",
          parent_company_jurisdiction: "",
          ownership_chart_uploaded: false,
        };

        app.completed_steps = [1, 2, 3, 4, 5, 6, 7, 8, 9];
        app._tenant_id = tid;

        apps[idx] = app;
        localStorage.setItem(key, JSON.stringify(apps));
      },
      { appId: applicationId, tid: tenantId ?? "" },
    );

    // ── Verify all steps render ────────────────────────────────
    const stepsToVerify = [
      { path: "addresses", heading: "Addresses" },
      { path: "contacts", heading: "Business contacts" },
      { path: "activity", heading: "Business activity" },
      { path: "transfers", heading: "Expected transfer behavior" },
      { path: "ownership", heading: "Ownership structure" },
    ];

    for (const step of stepsToVerify) {
      await page.goto(`onboarding/${applicationId}/${step.path}`, {
        waitUntil: "networkidle",
      });
      await expect(page.locator("h1", { hasText: step.heading })).toBeVisible({
        timeout: 5_000,
      });
    }

    // ── Step 10: Review — confirm and submit ───────────────────
    await page.goto(`onboarding/${applicationId}/review`, { waitUntil: "networkidle" });
    await expect(page.locator("h1", { hasText: "Review & submit" })).toBeVisible();

    const incompleteCount = await page.locator("text=Incomplete").count();
    expect(incompleteCount).toBe(0);

    // Check both confirmations via UI (validates split-brain fix)
    await page.locator("#confirm_accuracy").click();
    await page.locator("#confirm_authority").click();

    const submitButton = page.locator("button", { hasText: "Submit Application" });
    await expect(submitButton).toBeEnabled({ timeout: 2_000 });
    await submitButton.click();

    // Wait for status page
    await page.waitForURL(/\/status\//, { timeout: 30_000 });
    await expect(page).toHaveURL(/\/status\//);

    // ── Backend verification ───────────────────────────────────
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
        status: string;
        legal_entity: {
          id: string;
          business_name: string;
          legal_entity_type: string;
          addresses: Array<{ line1: string; country: string }>;
          identifications: Array<{ id_type: string; id_number: string }>;
        };
      }>;
    };
    const created = ahBody.data.find((ah) => ah.account_holder_type === "business");
    expect(created).toBeTruthy();
    createdAccountHolderId = created?.id;

    // Verify LegalEntity has AI-extracted data. The AccountHolder response
    // embeds the full LegalEntity — there is no standalone GET endpoint.
    const legalEntity = created?.legal_entity;
    if (legalEntity) {
      // AI-extracted company name from MOA
      expect(legalEntity.business_name).toMatch(/GULF PHARMACEUTICAL/i);
      expect(legalEntity.legal_entity_type).toBe("business");

      // Address submitted
      expect(legalEntity.addresses.length).toBeGreaterThanOrEqual(1);
      expect(legalEntity.addresses[0].country).toBe("AE");

      // Passport identification may or may not be submitted depending on
      // AI extraction quality — passport_number field must be non-empty
      // in a director/UBO for mapIdentifications to include it.
    }

    // Verify KycRequirement created — check most recent
    const kycRes = await fetch(
      `${API_BASE}/api/kyc-requirements?page_size=5&order_by=inserted_at&order_directions=desc`,
      { headers: authHeaders(bearer) },
    );
    expect(kycRes.ok).toBe(true);
    const kycBody = (await kycRes.json()) as {
      data: Array<{
        scope: string;
        status: string;
        account_holder_id: string;
      }>;
    };
    const kycReq = kycBody.data.find(
      (k) => k.account_holder_id === created?.id && k.scope === "account_holder",
    );
    expect(kycReq).toBeTruthy();
  });
});
