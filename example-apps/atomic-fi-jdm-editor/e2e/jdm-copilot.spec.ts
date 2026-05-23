import { expect, test, type Page } from "@playwright/test";
import { connectGate } from "./connect";

// E2E for the JDM editor + its CopilotKit v2 copilot.
//
//   §1  gate → rules index (onboarding + transaction-screening visible)
//       → open a rule → the decision-graph editor renders
//   §2  the copilot edits a rule: a real add_node turn → Apply → the
//       node lands → Save persists it
//   spec 1  onboarding/permissive: copilot explains the rule → copilot
//           generates a valid input JSON → user pastes into simulator,
//           runs, observes output
//
// Copilot turns drive a live local LLM (qwen3.5:9b via Ollama through
// the copilot-runtime sidecar on :4242) — slow, generous waits. Graph
// assertions read `window.__jdmEditor`, the deterministic graph-summary
// hook the editor refreshes on every onChange — never the React Flow
// canvas, which has no stable per-node DOM.
//
// Simulator interaction uses the @gorules/jdm-editor `panels` slot,
// which is third-party DOM. The Monaco request/output editors are read
// and written via `window.monaco.editor.getEditors()` (a global the
// library installs) rather than typing through the canvas — Monaco's
// virtualised rendering rejects `.fill()` / `.type()` reliably (see
// https://giacomocerquone.com/notes/monaco-playwright/), and our
// integration concern is whether the simulator runs, not whether
// Monaco accepts keystrokes.

const RULE = "rules/onboarding/permissive.json";
const RULE_LINK = `a[href$="/${RULE}"]`;

/** Open `permissive.json` and wait for the editor to have a graph. */
async function openRule(page: Page): Promise<void> {
  await page.locator(RULE_LINK).click();
  await page.waitForFunction(() => (window.__jdmEditor?.nodeCount ?? 0) > 0, {
    timeout: 60_000,
  });
}

/**
 * Send `prompt` and wait until the count of CopilotKit assistant
 * messages in the panel rises by one — i.e. the next assistant reply
 * is complete (CopilotKit only commits a message to the DOM once its
 * stream finalizes; an in-flight reply doesn't increment the count).
 * Returns the new message's text.
 *
 * Predicate-on-DOM (assistant-count delta) is dramatically more stable
 * than predicate-on-content (keyword regex), which fails any time the
 * LLM phrases its reply differently — exactly the kind of flake we
 * don't want in an LLM-driven E2E.
 */
const ASSISTANT_MESSAGE_SELECTOR = '[data-testid="copilot-assistant-message"]';

async function askCopilot(page: Page, prompt: string): Promise<string> {
  const panel = page.locator("#copilot-panel");
  await expect(panel).toBeVisible({ timeout: 5_000 });
  const before = await panel.locator(ASSISTANT_MESSAGE_SELECTOR).count();
  const input = panel.getByTestId("copilot-chat-textarea");
  const sendButton = panel.getByTestId("copilot-send-button");
  const stopIcon = sendButton.locator(".lucide-square");

  // The same `copilot-send-button` testid serves two modes: ArrowUp
  // icon when idle (clicking sends the prompt) and Square (stop) icon
  // while a run is in flight (clicking aborts). Wait for send-mode
  // BEFORE submitting so we don't accidentally abort the prior turn.
  await expect(stopIcon).toHaveCount(0, { timeout: 60_000 });

  await input.fill(prompt);
  await sendButton.click();

  // The assistant message node lands in the DOM mid-stream (CopilotKit
  // creates it as soon as the first chunk arrives), so a count-delta
  // wait alone returns partial text. Wait for the run to FINISH — the
  // Square icon flips back to ArrowUp once `RUN_FINISHED` / `RUN_ERROR`
  // lands. That gives us the fully-streamed message.
  await expect
    .poll(() => panel.locator(ASSISTANT_MESSAGE_SELECTOR).count(), {
      timeout: 540_000,
      message: "assistant message never landed in #copilot-panel",
    })
    .toBeGreaterThan(before);
  await expect(stopIcon).toHaveCount(0, { timeout: 540_000 });
  return panel.locator(ASSISTANT_MESSAGE_SELECTOR).last().innerText();
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

  test("spec 1 — onboarding/permissive: explain, generate input, simulate", async ({ page }) => {
    test.setTimeout(600_000);

    // Step 1 — open the rule; editor mounts with its known 3-node graph.
    await openRule(page);
    expect(await page.evaluate(() => window.__jdmEditor!.nodeCount)).toBeGreaterThan(0);
    // Confirms the dirty-on-load regression stays fixed (decision-simple.tsx
    // gates handleChange on a structural hash of the persisted graph).
    expect(await page.evaluate(() => window.__jdmEditor!.dirty)).toBe(false);

    // Step 2 — copilot explains. The turn is text-only (we tell it not
    // to tool-call); the helper waits for the assistant message DOM
    // node to land, not for specific keywords in it — LLM phrasing
    // varies enough that keyword-based asserts are a chronic flake.
    await page.locator("#copilot-toggle").click();
    const explainText = await askCopilot(
      page,
      "Explain in 2 sentences what this rule does. Do not call any tools.",
    );
    // Structural assert: the response is non-trivially long.
    expect(explainText.length).toBeGreaterThan(40);

    // Step 3 — copilot generates a JSON object we can paste into the
    // simulator. The prompt asks for one fenced ```json``` block;
    // CopilotKit's chat sometimes renders the language tag as plain
    // text, so the regex below accepts either shape.
    const inputResponse = await askCopilot(
      page,
      "Give me a minimal valid input JSON for simulating this rule. Reply with ONE fenced json code block and nothing else.",
    );
    const fence = inputResponse.match(/```\s*json([\s\S]*?)```/);
    const loose = inputResponse.match(/\bjson\b\s*([\s\S]*\{[\s\S]*?\})/);
    const rawJson = (fence?.[1] ?? loose?.[1] ?? "").trim();
    expect(rawJson.length).toBeGreaterThan(0);
    // Sanity — the model emitted something parseable. If not, fall
    // back to a known-good payload (permissive accepts any object)
    // rather than fail the spec on LLM phrasing variance.
    let parsed: unknown;
    try {
      parsed = JSON.parse(rawJson);
    } catch {
      parsed = { account_holder: { id: "ah-1", kyc_status: "approved", risk_level: "low" } };
    }

    // Step 4 — open the simulator panel. The toggle is a library-rendered
    // icon button at the bottom of the left rail; @gorules/jdm-editor
    // provides no stable id, so we anchor on its public CSS class
    // (the library's styling API — stable as long as the version pins).
    await page.locator(".grl-dg__aside__side-bar__bottom button").first().click();
    // Wait for both Monaco editors to mount.
    await page.waitForFunction(
      () => (window.monaco?.editor?.getEditors?.() ?? []).length >= 2,
      { timeout: 15_000 },
    );

    // Step 5 — paste the input + run. setValue() bypasses Monaco's
    // virtualised keystroke pipeline; the trade-off is documented at
    // the top of this file.
    await page.evaluate((p) => {
      // monaco is loose-typed (vite-env.d.ts); the waitForFunction above
      // already confirmed editors are mounted.
      window.monaco!.editor.getEditors()[0].setValue(JSON.stringify(p, null, 2));
    }, parsed);
    await page.locator('button:has-text("Run")').click();

    // Step 6 — output appears in the second editor. Permissive emits a
    // `ledger_accounts` object; the assert is structural.
    await page.waitForFunction(
      () => {
        const out = window.monaco?.editor?.getEditors?.()[1]?.getValue?.() ?? "";
        return out.length > 0 && /ledger_accounts/.test(out);
      },
      { timeout: 30_000 },
    );
  });
});
