/**
 * Playwright global setup — pre-warm Ollama before any test runs.
 *
 * The JDM editor's copilot drives `qwen3.5:9b` via Ollama. Ollama keeps
 * the model resident in memory only while it's actively used; after
 * its keep-alive window (5 minutes by default) it unloads. Cold-loading
 * a 9 GB model from disk can take several minutes — long enough to
 * eat a whole per-turn 540 s budget before any token streams.
 *
 * The simplest fix is to fire a one-token generate against the model
 * up front, so by the time the JDM project's tests dial the runtime
 * the model is already resident. `keep_alive: '15m'` extends the
 * idle horizon to cover a full suite. Idempotent — if the model is
 * already loaded the call returns in milliseconds.
 *
 * Skipped silently when:
 *   • SKIP_OLLAMA_WARMUP=1 (CI / Ollama-less smoke runs)
 *   • Ollama isn't reachable (no JDM project test will run; this is
 *     not our crash to own — the suite itself surfaces it cleanly).
 */
async function warmOllama(): Promise<void> {
  if (process.env.SKIP_OLLAMA_WARMUP === "1") return;

  const baseUrl = process.env.OLLAMA_BASE_URL ?? "http://localhost:11434";
  const model = process.env.LLM_MODEL ?? "qwen3.5:9b";

  // eslint-disable-next-line no-console -- diagnostic for the suite operator
  console.log(`[playwright global-setup] warming Ollama ${model} at ${baseUrl} …`);

  let reachable = false;
  try {
    const ping = await fetch(`${baseUrl}/api/tags`, {
      signal: AbortSignal.timeout(2_000),
    });
    reachable = ping.ok;
  } catch {
    // Connect refused / DNS / timeout — leave the suite to surface it.
  }
  if (!reachable) {
    // eslint-disable-next-line no-console -- diagnostic
    console.log(`[playwright global-setup] Ollama not reachable; skipping warmup.`);
    return;
  }

  // 5-minute generous deadline; cold-load of a 9 GB model from a slow
  // disk has been observed to take ~3 minutes on first run.
  const started = Date.now();
  try {
    await fetch(`${baseUrl}/api/generate`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        model,
        prompt: "ok",
        stream: false,
        keep_alive: "15m",
        options: { num_predict: 1 },
      }),
      signal: AbortSignal.timeout(300_000),
    });
  } catch (err) {
    // eslint-disable-next-line no-console -- diagnostic
    console.log(`[playwright global-setup] Ollama warmup failed (continuing): ${(err as Error).message}`);
    return;
  }
  // eslint-disable-next-line no-console
  console.log(`[playwright global-setup] Ollama warmed in ${((Date.now() - started) / 1000).toFixed(1)}s.`);
}

export default async function globalSetup(): Promise<void> {
  await warmOllama();
}
