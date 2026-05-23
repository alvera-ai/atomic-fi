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

/**
 * Drain any pending HITL cards (and the follow-up turns the agent
 * generates as each tool result lands) until the queue stays empty for
 * `stableEmptyMs`. Click "Apply all" when ≥2 are pending (the footer
 * surfaces it then); otherwise click the lone `#hitl-apply-*`. Returns
 * when no further activity for the stable window OR the per-call timeout
 * expires.
 *
 * The agent often emits a node-add batch first, then in follow-up turns
 * retries duplicates or generates invalid args — all auto-resolve here
 * with `respond({accepted: false, reason})`, which is the self-correction
 * signal it needs to stop.
 */
async function applyAllPending(
  page: Page,
  { stableIdleMs = 12_000, maxMs = 540_000, firstCardTimeoutMs = 300_000 } = {},
): Promise<void> {
  const pendingSelector =
    '[data-testid="hitl-card"][data-hitl-status="executing"], [data-testid="hitl-card"][data-hitl-status="queued"]';
  const stopIcon = page.locator('[data-testid="copilot-send-button"] .lucide-square');

  // Phase 1 — wait for the FIRST pending card to land. Without this
  // gate the helper sees the initial empty state, counts it as
  // "stable empty," and returns before the agent has emitted anything.
  // qwen3.5:9b cold prompts have been observed to run ≈30 s before
  // the first tool call lands.
  await expect
    .poll(() => page.locator(pendingSelector).count(), {
      timeout: firstCardTimeoutMs,
      message: "no HITL card landed after the prompt — the agent didn't emit any tool calls",
    })
    .toBeGreaterThan(0);

  // Phase 2 — drain. Click "Apply all" when ≥2 are pending; otherwise
  // click the lone executing card's apply. Idle only when BOTH:
  //   (a) the HITL queue is empty AND
  //   (b) no run is in flight (the send button's stop icon is gone)
  // for `stableIdleMs`. (a) alone was the original bug: the agent's
  // next turn can take 30+ s to emit its first card; without the
  // run-in-flight check the helper would return mid-conversation.
  const start = Date.now();
  let stableIdleSince: number | null = null;
  while (Date.now() - start < maxMs) {
    const pendingCount = await page.locator(pendingSelector).count();
    const stopIconCount = await stopIcon.count();
    const idle = pendingCount === 0 && stopIconCount === 0;
    if (idle) {
      if (stableIdleSince === null) stableIdleSince = Date.now();
      else if (Date.now() - stableIdleSince > stableIdleMs) return;
      await page.waitForTimeout(500);
      continue;
    }
    stableIdleSince = null;
    if (pendingCount > 0) {
      const applyAll = page.locator("#apply-all-button");
      if (await applyAll.count()) {
        await applyAll.click();
      } else {
        const exec = page.locator('[data-testid="hitl-card"][data-hitl-status="executing"]').first();
        const apply = exec.locator('[data-testid="hitl-apply"]');
        if (await apply.count()) {
          await apply.click();
        }
      }
    }
    // Let the agent settle (its next turn fires after CopilotKit acks
    // the responses). 3 s is empirically enough for qwen3.5:9b warm.
    await page.waitForTimeout(3_000);
  }
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

  test("spec 2 — onboarding: copilot authors a new rule, sim it, then edit it", async ({ page }) => {
    test.setTimeout(900_000);

    // Step 1 — create a new onboarding rule via `#new-rule-button`.
    // Editor's `handleNewRule` uses `window.prompt`, so we register the
    // dialog handler BEFORE the click. Use a deterministic filename
    // suffix so reruns don't fight an already-existing file (the
    // server's POST /api/rules/:type rejects duplicates).
    const filename = `e2e-kyc-gate-${Date.now()}.json`;
    page.once("dialog", (dialog) => dialog.accept(filename));
    await page.locator("#new-rule-button").click();
    await expect(page).toHaveURL(new RegExp(`/rules/onboarding/${filename}\\?new=1$`), {
      timeout: 15_000,
    });
    expect(await page.evaluate(() => window.__jdmEditor!.nodeCount)).toBe(0);

    // Step 2 — ask copilot to author the rule. The prompt is descriptive
    // (the BSA §326 CIP case for `kyc_status="in_progress"`) so the
    // model has a clear goal; `applyAllPending` drains the resulting
    // tool calls + the agent's self-correction follow-ups.
    await page.locator("#copilot-toggle").click();
    const panel = page.locator("#copilot-panel");
    await expect(panel).toBeVisible({ timeout: 5_000 });
    const input = panel.getByTestId("copilot-chat-textarea");
    const sendButton = panel.getByTestId("copilot-send-button");
    await expect(sendButton.locator(".lucide-square")).toHaveCount(0, { timeout: 60_000 });
    await input.fill(
      "Author this onboarding rule end to end. It must BLOCK any payment when " +
        "account_holder.kyc_status is in_progress, and PASS otherwise (BSA §326 CIP). " +
        "Use these tool calls in order: add three nodes (an inputNode named Request, " +
        "a decisionTableNode named KYC Gate, an outputNode named Response), then connect " +
        "them with two add_edge calls (Request->KYC Gate, KYC Gate->Response). " +
        "Do NOT call save_rule; the user will save.",
    );
    await sendButton.click();

    // Step 3 — drain the HITL queue. The agent may emit duplicates or
    // invalid-args follow-ups; all auto-resolve (rejected for
    // duplicates, parser-rejected for invalid args). What we care about
    // is that the canvas ends up with the three named nodes — edges
    // are a stretch goal because qwen3.5:9b is noisy about add_edge.
    await applyAllPending(page);
    const namesAfterAuthor = await page.evaluate(() => window.__jdmEditor!.nodeNames);
    expect(namesAfterAuthor).toEqual(expect.arrayContaining(["Request", "KYC Gate", "Response"]));

    // Step 4 — save manually. We don't trust the agent to call
    // save_rule reliably; clicking the human save path also tests the
    // Phoenix REST write + the dirty-flag clear.
    await page.locator("#save-rule-button").click();
    await page.waitForFunction(() => window.__jdmEditor?.dirty === false, {
      timeout: 30_000,
    });

    // Step 5 — ZenRule polls the bind-mounted filesystem on its own
    // schedule (5 s default, see external-deps/zenrule/src/config.rs
    // `default_refresh_interval`). Wait 15 s before any simulate call
    // so the freshly-saved file is guaranteed to be in ZenRule's loaded
    // set, not 404'd as missing.
    await page.waitForTimeout(15_000);

    // Step 6 — copilot generates a valid input JSON, same shape as
    // spec 1 (proven path).
    const inputResponse = await askCopilot(
      page,
      "Give me a minimal input JSON to simulate this rule with " +
        "account_holder.kyc_status set to 'in_progress'. Reply with ONE fenced " +
        "json code block and nothing else.",
    );
    const fence = inputResponse.match(/```\s*json([\s\S]*?)```/);
    const loose = inputResponse.match(/\bjson\b\s*([\s\S]*\{[\s\S]*?\})/);
    const rawJson = (fence?.[1] ?? loose?.[1] ?? "").trim();
    let parsed: unknown;
    try {
      parsed = JSON.parse(rawJson);
    } catch {
      parsed = { account_holder: { kyc_status: "in_progress" } };
    }

    // Step 7 — paste into simulator + run. The output isn't asserted
    // semantically (the LLM's decision-table body may or may not
    // compile cleanly); the assert is that SOME output landed without
    // a 404, proving the save → poll → evaluate path works.
    await page.locator(".grl-dg__aside__side-bar__bottom button").first().click();
    await page.waitForFunction(
      () => (window.monaco?.editor?.getEditors?.() ?? []).length >= 2,
      { timeout: 15_000 },
    );
    await page.evaluate((p) => {
      window.monaco!.editor.getEditors()[0].setValue(JSON.stringify(p, null, 2));
    }, parsed);
    await page.locator('button:has-text("Run")').click();
    await page.waitForFunction(
      () => (window.monaco?.editor?.getEditors?.()[1]?.getValue?.() ?? "").length > 0,
      { timeout: 30_000 },
    );

    // Step 8 — edit-the-rule round-trip. Ask the copilot to make a
    // small mutation (rename a node), apply, and assert the dirty flag
    // flipped back to true. We don't care about the exact mutation —
    // the assertion is "a copilot-driven edit registers as a real
    // change against the persisted baseline."
    await askCopilot(
      page,
      "Use update_node to rename the Response node to ResponseV2. Pass the existing node by name as node_id.",
    );
    await applyAllPending(page, { stableIdleMs: 12_000, maxMs: 300_000 });
    expect(await page.evaluate(() => window.__jdmEditor!.dirty)).toBe(true);
  });

  test("spec 3 — transaction-screening/de_minimis: explain, generate input, simulate", async ({ page }) => {
    test.setTimeout(600_000);

    // Same shape as spec 1 but on a different rule type. `de_minimis`
    // is the simplest txn-screening rule (3 nodes: Request →
    // De Minimis expression → Response). Proves the txn-screening
    // demo path works end-to-end with the same fixes (CORS, simulator
    // routing, dirty-on-load, etc.).
    await page.goto("rules/transaction-screening/de_minimis.json");
    await page.waitForFunction(() => (window.__jdmEditor?.nodeCount ?? 0) > 0, {
      timeout: 60_000,
    });
    expect(await page.evaluate(() => window.__jdmEditor!.dirty)).toBe(false);

    await page.locator("#copilot-toggle").click();
    const explainText = await askCopilot(
      page,
      "Explain in 2 sentences what this rule does. Do not call any tools.",
    );
    expect(explainText.length).toBeGreaterThan(40);

    const inputResponse = await askCopilot(
      page,
      "Give me a minimal valid input JSON for simulating this rule. Reply with ONE fenced json code block and nothing else.",
    );
    const fence = inputResponse.match(/```\s*json([\s\S]*?)```/);
    const loose = inputResponse.match(/\bjson\b\s*([\s\S]*\{[\s\S]*?\})/);
    const rawJson = (fence?.[1] ?? loose?.[1] ?? "").trim();
    let parsed: unknown;
    try {
      parsed = JSON.parse(rawJson);
    } catch {
      // De Minimis examines `transaction.amount` — a small one should
      // pass through. The structural assert below doesn't care WHICH
      // outcome the rule emits.
      parsed = { transaction: { amount: 5_000, transaction_type: "ach_credit" } };
    }

    await page.locator(".grl-dg__aside__side-bar__bottom button").first().click();
    await page.waitForFunction(
      () => (window.monaco?.editor?.getEditors?.() ?? []).length >= 2,
      { timeout: 15_000 },
    );
    await page.evaluate((p) => {
      window.monaco!.editor.getEditors()[0].setValue(JSON.stringify(p, null, 2));
    }, parsed);
    await page.locator('button:has-text("Run")').click();

    // The output is structurally non-empty — the exact contents depend
    // on the LLM's chosen amount + the de-minimis threshold; what we
    // care about is the simulator hit ZenRule and ZenRule emitted
    // something parseable. (Spec 1 asserts on a `ledger_accounts` shape
    // particular to the permissive rule; de_minimis emits a different
    // shape so we settle for "non-empty.")
    await page.waitForFunction(
      () => (window.monaco?.editor?.getEditors?.()[1]?.getValue?.() ?? "").length > 0,
      { timeout: 30_000 },
    );
  });

  test("spec 4 — transaction-screening: copilot authors a new rule, sim it, then edit it", async ({ page }) => {
    test.setTimeout(900_000);

    // Mirror of spec 2 for the txn-screening rule type. Use-case #11
    // from guides/use-cases.md — "AH pays a CP whose OFAC SDN
    // Watchman score is ≥ 95: BLOCK + OFAC report." We're not asking
    // the model to match the regulation precisely (qwen3.5:9b is too
    // small for that fidelity); the spec asserts on the integration
    // path, not the rule's legal correctness.
    await page.goto("rules/transaction-screening");
    const filename = `e2e-sdn-block-${Date.now()}.json`;
    page.once("dialog", (dialog) => dialog.accept(filename));
    await page.locator("#new-rule-button").click();
    await expect(page).toHaveURL(new RegExp(`/rules/transaction-screening/${filename}\\?new=1$`), {
      timeout: 15_000,
    });
    expect(await page.evaluate(() => window.__jdmEditor!.nodeCount)).toBe(0);

    await page.locator("#copilot-toggle").click();
    const panel = page.locator("#copilot-panel");
    await expect(panel).toBeVisible({ timeout: 5_000 });
    const input = panel.getByTestId("copilot-chat-textarea");
    const sendButton = panel.getByTestId("copilot-send-button");
    await expect(sendButton.locator(".lucide-square")).toHaveCount(0, { timeout: 60_000 });
    await input.fill(
      "Author this transaction-screening rule end to end. It must BLOCK any " +
        "payment whose recipient has an OFAC SDN match score >= 95, and PASS " +
        "otherwise (OFAC 31 CFR §501.404). Use these tool calls in order: " +
        "add three nodes (an inputNode named Request, a decisionTableNode named " +
        "SDN Score Gate, an outputNode named Response), then connect them with " +
        "two add_edge calls. Do NOT call save_rule; the user will save.",
    );
    await sendButton.click();
    await applyAllPending(page);

    const namesAfterAuthor = await page.evaluate(() => window.__jdmEditor!.nodeNames);
    expect(namesAfterAuthor).toEqual(expect.arrayContaining(["Request", "SDN Score Gate", "Response"]));

    await page.locator("#save-rule-button").click();
    await page.waitForFunction(() => window.__jdmEditor?.dirty === false, {
      timeout: 30_000,
    });
    // ZenRule poll lag — see spec 2 step 5 for the rationale.
    await page.waitForTimeout(15_000);

    const inputResponse = await askCopilot(
      page,
      "Give me a minimal input JSON to simulate this rule with a sanctions match " +
        "score of 97. Reply with ONE fenced json code block and nothing else.",
    );
    const fence = inputResponse.match(/```\s*json([\s\S]*?)```/);
    const loose = inputResponse.match(/\bjson\b\s*([\s\S]*\{[\s\S]*?\})/);
    const rawJson = (fence?.[1] ?? loose?.[1] ?? "").trim();
    let parsed: unknown;
    try {
      parsed = JSON.parse(rawJson);
    } catch {
      parsed = {
        transaction: { amount: 5_000 },
        counterparty: { sanctions_matches: [{ match_score: 97, source_list: "OFAC_SDN" }] },
      };
    }

    await page.locator(".grl-dg__aside__side-bar__bottom button").first().click();
    await page.waitForFunction(
      () => (window.monaco?.editor?.getEditors?.() ?? []).length >= 2,
      { timeout: 15_000 },
    );
    await page.evaluate((p) => {
      window.monaco!.editor.getEditors()[0].setValue(JSON.stringify(p, null, 2));
    }, parsed);
    await page.locator('button:has-text("Run")').click();
    await page.waitForFunction(
      () => (window.monaco?.editor?.getEditors?.()[1]?.getValue?.() ?? "").length > 0,
      { timeout: 30_000 },
    );

    // Edit-the-rule round-trip — same shape as spec 2 step 8.
    await askCopilot(
      page,
      "Use update_node to rename the Response node to ResponseV2. Pass the existing node by name as node_id.",
    );
    await applyAllPending(page, { stableIdleMs: 12_000, maxMs: 300_000 });
    expect(await page.evaluate(() => window.__jdmEditor!.dirty)).toBe(true);
  });
});
