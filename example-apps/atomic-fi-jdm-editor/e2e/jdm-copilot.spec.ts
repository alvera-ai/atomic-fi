import { expect, test, type Page } from "@playwright/test";
import { connectGate } from "./connect";

// E2E for the JDM editor + its CopilotKit v2 copilot.
//
//   §1  gate → rules index (onboarding + transaction-screening visible)
//       → open a rule → the decision-graph editor renders
//   §2  the copilot edits a rule: a real add_node turn → Apply → the
//       node lands → Save persists it
//
// §2 drives a live copilot turn — qwen3.5:9b via Ollama, posted to the
// copilot-runtime sidecar (CopilotKit v2 / AG-UI protocol). Graph
// assertions read `window.__jdmEditor`, the deterministic graph-summary
// hook the editor refreshes on every onChange — never the React Flow
// canvas, which has no stable per-node DOM.

const RULE = "rules/onboarding/permissive.json";
const RULE_LINK = `a[href$="/${RULE}"]`;

/** Open `permissive.json` and wait for the editor to have a graph. */
async function openRule(page: Page): Promise<void> {
  await page.locator(RULE_LINK).click();
  await page.waitForFunction(() => (window.__jdmEditor?.nodeCount ?? 0) > 0, {
    timeout: 60_000,
  });
}

test.describe("JDM editor + copilot (v2)", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("rules/onboarding");
    await connectGate(page);
  });

  test("§1 — rules index lists both rule types, editor renders", async ({ page }) => {
    // Both rule types are visible on the index.
    await expect(page.getByRole("tab", { name: /Onboarding/ })).toBeVisible();
    await expect(page.getByRole("tab", { name: /Transaction screening/ })).toBeVisible();

    // Opening a rule mounts the decision-graph editor; the deterministic
    // hook reports the loaded graph.
    await openRule(page);
    expect(await page.evaluate(() => window.__jdmEditor!.nodeCount)).toBeGreaterThan(0);
  });

  test("§2 — copilot edits a rule via add_node, then it saves", async ({ page }) => {
    test.setTimeout(600_000);

    await openRule(page);
    const nodesBefore = await page.evaluate(() => window.__jdmEditor!.nodeCount);

    // Open the v2 copilot panel and ask it to add a node.
    await page.locator("#copilot-toggle").click();
    const panel = page.locator("#copilot-panel");
    const input = panel.getByTestId("copilot-chat-textarea");
    await input.fill("Add an expression node named amount-floor to the graph.");
    await input.press("Enter");

    // The turn streams an add_node tool call → a Human-in-the-Loop
    // PreviewCard with Apply / Reject. qwen3.5:9b is a slow thinking
    // model — the runner waits, generously.
    const card = panel.locator(".ant-card", { hasText: "add_node" });
    await expect(card).toBeVisible({ timeout: 540_000 });
    await card.getByRole("button", { name: "Apply" }).click();

    // Deterministic: the node landed in the graph.
    await page.waitForFunction(
      (before) => (window.__jdmEditor?.nodeCount ?? 0) > before,
      nodesBefore,
      { timeout: 60_000 },
    );

    // Save — the rules API write clears the dirty flag.
    await page.locator("#save-rule-button").click();
    await page.waitForFunction(() => window.__jdmEditor?.dirty === false, {
      timeout: 30_000,
    });
  });
});
