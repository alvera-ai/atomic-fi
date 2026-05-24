# JDM editor — Playwright session log

Live-discovery log for the **atomic-fi JDM editor** (CopilotKit v2 / AG-UI) on
`feat/gh-49-single-app-demo-build`. Each scenario records the prompt driven
through the chat, the expected HITL card, and the deterministic editor-state
assertion. Lines marked **NEW** are added by this session and will be
codified as Playwright tests under `example-apps/atomic-fi-jdm-editor/e2e/`.

Stable selector contract (audited 2026-05-22):

| Element | Selector |
|---|---|
| Connect-gate input | `#api-key` |
| Connect-gate submit | `#connect-button` |
| Copilot toggle | `#copilot-toggle` |
| Copilot panel | `#copilot-panel` |
| Save button | `#save-rule-button` |
| Back to rules | `#back-to-rules-button` |
| Chat input | `[data-testid="copilot-chat-textarea"]` |
| HITL card | `.ant-card` (filtered by `hasText`) |
| Editor state hook | `window.__jdmEditor` (`nodeCount`, `nodeNames`, `edgeCount`, `dirty`) |

All chat-driven scenarios use a 600-second test timeout / 540-second
per-wait — `qwen3.5:9b` via Ollama is a slow thinking model on cold start.

---

## §1 — Rules index + editor mount

**Status:** ✅ green (already in `e2e/jdm-copilot.spec.ts`).

- Gate clears with `alvera_root_api_key_dev`.
- Index lists both `Onboarding` and `Transaction screening` tabs.
- Opening `rules/onboarding/permissive.json` hydrates `window.__jdmEditor`
  with `nodeCount > 0`.

---

## §2 — Add a node via copilot

**Status:** ✅ green (already in `e2e/jdm-copilot.spec.ts`).

- Prompt: `Add an expression node named amount-floor to the graph.`
- Expected: `add_node` PreviewCard with Apply/Reject.
- Apply → `nodeCount` increases, dirty flips to true.
- Save → dirty flips back to false.

---

## §3 — Modify a node via copilot **NEW**

**Status:** ⏳ being verified live.

- Open `rules/transaction-screening/ah_country_kp_residence.json`.
- Prompt: `Add Crimea (CR) to the sanctioned country list in this rule.
  Use update_node — do not just describe the change.`
- Expected: `update_node` PreviewCard with Apply/Reject. Patch shows the
  new sanctioned-country array containing `'CR'`.
- Apply → `window.__jdmEditor.nodeNames` is unchanged, but the node's
  `content.source` substring now contains `'CR'`. The dirty flag flips
  to true; Save clears it.
- **Regression guard** (added this session): without an
  `Authoring instructions` readable in `useEditorReadables`, qwen3.5:9b
  responds with text-only ("I will update the rule…") instead of firing
  `update_node`. The readable must be present and projected to the LLM
  system message via `context_items` (runtime log line should show
  `context_items=8` or more, not `7`).

---

## §4 — Create a new onboarding rule **NEW**

**Status:** ⏳ pending.

- From `rules/onboarding` index.
- Prompt: `Create a new onboarding rule named kyc-gate.json with a
  decision-table that blocks payments when account_holder.kyc_status is
  in_progress, rejected, or expired, and allows otherwise.`
- Expected sequence of HITL cards:
  1. `create_rule` (rule_type=onboarding, filename=kyc-gate.json)
  2. `add_node` × 3 (Request, KYC Payment Gate decision-table, Response)
  3. `add_edge` × 2 (request→gate, gate→response)
  4. `save_rule`
- Apply each → `window.__jdmEditor.nodeCount === 3`,
  `window.__jdmEditor.edgeCount === 2`,
  `window.location.pathname` ends with `/rules/onboarding/kyc-gate.json`,
  `dirty === false` after save.

---

## §5 — Create a new transaction-screening rule **NEW**

**Status:** ⏳ pending.

- From `rules/transaction-screening` index.
- Prompt: `Create a new transaction-screening rule named
  large-cash-flag.json that flags ACH credits > $10,000 for review.`
- Expected: same shape as §4 (create_rule → add_node × N →
  add_edge × N → save_rule), with a `decisionTableNode` whose
  `inputs[]` reads `transaction.amount` and
  `transaction.transaction_type`, and an `outputs[]` writing
  `transaction.rule = "review"`.

---

## §6 — Simulate a rule **NEW**

**Status:** ⏳ pending.

- On an open rule that has at least one saved revision.
- Prompt: `Simulate this rule with a context where
  account_holder.kyc_status is "approved".`
- Expected: `simulate_rule` PreviewCard with the `context_json` arg as a
  **JSON-encoded string** (not an object — see
  `prompts/system.md` §"context_json is a JSON-ENCODED STRING").
- Apply → next turn's `last_simulation` readable contains the trace
  (`{ context, trace, error }`), and the editor's GraphSimulator panel
  renders the trace.

---

## Bucket classification

A — Flake (intermittent, model timing): retry once with the same prompt;
if green on retry, log here and move on.

B — Intentional (model chose to ask a clarifying question instead of
tool-calling): refine the prompt (more directive) and re-run. Only
escalate if a strictly directive prompt still doesn't tool-call.

C — Stale locator: update the selector contract in this file and the
spec. Selectors must be predictable HTML `id`s on interactive elements
(per the project memory `feedback_playwright_predictable_ids`).

D — Regression: file a GH sub-issue under GH-49, attach the runtime
log line + the chat panel content captured via
`playwright-cli eval`.

---

## Live notes — 2026-05-22

- v1 worktree (port 5174) is the reference; v2 stack (port 4100) must
  match.
- Two runtime fixes shipped this session:
  - Generic sidecar projects `ctx.input.context[]` into
    `streamText({system, …})` (`external-deps/copilot-runtime/src/runtime.ts`).
  - `<CopilotChat>` wrapped in `<CopilotChatConfigurationProvider
    threadId={stableUuid}>` (`src/pages/decision-simple.tsx`) — without it
    every submit mints a new threadId (CopilotKit issue #2953).
- Editor-side change shipped this session:
  - 158-line JDM authoring `SYSTEM_PROMPT` re-introduced as the FIRST
    `useAgentContext` readable in `src/copilot/use-editor-readables.ts`
    (mirrors the prompt the v1 worktree runtime injected via
    `middleware.onBeforeRequest`). The runtime stays generic; the
    editor owns the domain.
- Open regression to track: "Thread already running" on concurrent
  `/run` requests with the same threadId — see
  `@copilotkit/runtime/dist/v2/runtime/runner/in-memory.mjs:30`. Either
  gate submits while a turn is in flight, or relax the runtime's
  in-memory event-store check.
- Open regression to track: `tool-params.ts` emits
  `required: ["content","position"]` on `add_node` because
  `z.unknown()` is required-by-default in zod-to-json-schema; the LLM
  dutifully sends `{content:{}, position:{}}`.
