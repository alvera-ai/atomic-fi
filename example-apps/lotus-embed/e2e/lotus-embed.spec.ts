import { expect, test } from "@playwright/test";

const BACKEND = "http://localhost:4100";

async function loginAndEmbed(page: import("@playwright/test").Page) {
  await page.goto("./");
  await expect(page.locator("h1")).toContainText("Lotus Embed");

  // Login with seeded creds (pre-filled)
  await page.locator("button", { hasText: "Login" }).click();
  await expect(page.locator("h2", { hasText: "Exchange Bearer" })).toBeVisible({
    timeout: 10_000,
  });

  // Exchange bearer for embed token
  await page.locator("button", { hasText: "Get Embed Token" }).click();
  await expect(page.locator("h2", { hasText: "Lotus Dashboard" })).toBeVisible({
    timeout: 10_000,
  });

  // Wait for iframe to load
  const iframe = page.locator("iframe[title='Lotus Dashboard']");
  await expect(iframe).toBeVisible();
  return page.frameLocator("iframe[title='Lotus Dashboard']");
}

test.describe("Lotus secure embed — full flow", () => {
  test.setTimeout(120_000);

  test.beforeEach(async () => {
    const res = await fetch(`${BACKEND}/api/info`).catch(() => null);
    test.skip(!res?.ok, "Backend not running on :4100");
  });

  test("login → embed → Lotus dashboard renders", async ({ page }) => {
    const frame = await loginAndEmbed(page);

    // Lotus should render its query editor page
    await expect(frame.locator("body")).toBeVisible({ timeout: 15_000 });
    const bodyText = await frame.locator("body").textContent({ timeout: 15_000 });
    expect(bodyText!.length).toBeGreaterThan(0);
  });

  test("run a SQL query inside the embedded Lotus dashboard", async ({ page }) => {
    const frame = await loginAndEmbed(page);

    // Lotus lands on the queries list — wait for it
    await frame.locator("#queries-page").waitFor({ timeout: 20_000 });

    // "Create your first query" is a direct LiveView navigate link
    await frame.locator("text=Create your first query").click();
    await frame.locator("#query-editor-page").waitFor({ timeout: 15_000 });

    // Wait for CodeMirror editor to initialize
    const cmContent = frame.locator(".cm-content");
    await cmContent.waitFor({ timeout: 10_000 });

    // Type SQL into CodeMirror (contenteditable div)
    await cmContent.click();
    await cmContent.pressSequentially("SELECT id, name, slug FROM tenants LIMIT 10", {
      delay: 5,
    });

    // Click Run Query button (pink circle with play icon)
    await frame.locator("#run-query-btn").click();

    // Wait for results table to render
    await expect(frame.locator("table tbody tr").first()).toBeVisible({ timeout: 15_000 });
  });

  test("AI assistant generates SQL query with Ollama", async ({ page }) => {
    const frame = await loginAndEmbed(page);

    // Lotus lands on queries list — navigate to editor
    await frame.locator("#queries-page").waitFor({ timeout: 20_000 });
    await frame.locator("text=Create your first query").click();
    await frame.locator("#query-editor-page").waitFor({ timeout: 15_000 });

    // Open the AI assistant panel
    const aiToggle = frame.locator("#ai-assistant-btn");
    await aiToggle.waitFor({ timeout: 10_000 });
    await aiToggle.click();

    // Wait for AI assistant panel to be visible
    await expect(frame.locator("#ai-conversation-history")).toBeVisible({ timeout: 5_000 });

    // Type a natural language query
    const chatInput = frame.locator("textarea#ai-message-input");
    await expect(chatInput).toBeVisible({ timeout: 5_000 });
    await chatInput.fill("Show me all tables in the database with their row counts");

    // Submit the message
    await frame.locator("#ai-message-form button[type='submit']").click();

    // Wait for AI response — should show a SQL query in a code block
    // The assistant generates SQL and wraps it in <pre><code>
    await expect(frame.locator("#ai-conversation-history pre code")).toBeVisible({
      timeout: 30_000,
    });

    // The response should contain SQL keywords
    const generatedSql = await frame
      .locator("#ai-conversation-history pre code")
      .first()
      .textContent();
    expect(generatedSql).toBeTruthy();
    expect(generatedSql!.toUpperCase()).toContain("SELECT");

    // Click "Use this query" to apply the generated SQL to the editor
    const useQueryButton = frame.locator("button", { hasText: "Use this query" }).first();
    await expect(useQueryButton).toBeVisible({ timeout: 5_000 });
    await useQueryButton.click();

    // The editor should now have the AI-generated SQL — run it
    await frame.locator("#run-query-btn").click();

    // Wait for results heading (appears for both success and error states)
    await expect(
      frame.locator("h2", { hasText: "Results" }),
    ).toBeVisible({ timeout: 15_000 });
  });

  test("rejects invalid embed token", async () => {
    const res = await fetch(`${BACKEND}/lotus?token=invalid`);
    expect(res.status).toBe(401);
    const body = await res.text();
    expect(body).toContain("Invalid embed token");
  });

  test("rejects missing embed token", async () => {
    const res = await fetch(`${BACKEND}/lotus`);
    expect(res.status).toBe(401);
    const body = await res.text();
    expect(body).toContain("Missing embed token");
  });

  test("refresh token re-enters token exchange step", async ({ page }) => {
    await page.goto("./");
    await page.locator("button", { hasText: "Login" }).click();
    await expect(page.locator("h2", { hasText: "Exchange Bearer" })).toBeVisible({
      timeout: 10_000,
    });
    await page.locator("button", { hasText: "Get Embed Token" }).click();
    await expect(page.locator("iframe")).toBeVisible({ timeout: 10_000 });

    // Click refresh — should go back to step 2, not step 1
    await page.locator("button", { hasText: "Refresh Token" }).click();
    await expect(page.locator("h2", { hasText: "Exchange Bearer" })).toBeVisible();
    await expect(page.locator("iframe")).not.toBeVisible();
  });
});
