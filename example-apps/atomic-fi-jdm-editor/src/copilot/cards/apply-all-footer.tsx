import React, { useEffect, useState } from 'react';
import { Button } from 'antd';

// Module-level registry + "auto-apply" mode flag.
//
// Background: CopilotKit serializes concurrent tool calls of the same action.
// When the agent emits add_node × 3 in one turn, CopilotKit only has ONE
// `executing` tool call at a time — the other two are demoted to `inProgress`
// with respond=undefined until the active one resolves. Naively snapshotting
// `pending` and firing every handle would call respond?.() on inactive cards,
// where the optional chain silently skips and the tool call stays awaiting.
//
// Solution: cards register in `pending` only when they're `executing` (real
// respond available). Apply-all flips a global `autoApplying` flag; whenever a
// card transitions to `executing` and registers, the registry auto-fires its
// pendingApply if the flag is on. The footer waits until pending stays empty
// for a stable window, then clears the flag.

type ApplyHandle = () => void;

const pending = new Set<ApplyHandle>();
const listeners = new Set<() => void>();
let autoApplying = false;

function notify(): void {
  listeners.forEach((fn) => fn());
}

export function isAutoApplying(): boolean {
  return autoApplying;
}

export function registerPending(apply: ApplyHandle): () => void {
  pending.add(apply);
  notify();
  if (autoApplying) {
    // Defer to a microtask so the card finishes mounting + its
    // onApplyRef.current is up to date before we fire.
    queueMicrotask(() => {
      if (autoApplying && pending.has(apply)) {
        apply();
      }
    });
  }
  return () => {
    pending.delete(apply);
    notify();
  };
}

export const ApplyAllFooter: React.FC = () => {
  const [count, setCount] = useState(pending.size);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const update = (): void => setCount(pending.size);
    listeners.add(update);
    return () => {
      listeners.delete(update);
    };
  }, []);

  if (count < 2 && !busy) return null;

  return (
    <div
      className="fixed bottom-20 right-4 px-3 py-2 rounded-md border border-rule bg-surface flex items-center gap-3 z-50 shadow"
      id="apply-all-footer"
      data-testid="apply-all-footer"
    >
      <span className="text-xs text-ink-muted" data-testid="apply-all-count">
        {busy
          ? `applying${count > 0 ? ` (${count} in flight)` : '…'}`
          : `${count} pending action${count === 1 ? '' : 's'}`}
      </span>
      <Button
        id="apply-all-button"
        data-testid="apply-all-button"
        size="small"
        type="primary"
        loading={busy}
        disabled={busy}
        onClick={async () => {
          if (busy) return;
          setBusy(true);
          autoApplying = true;
          try {
            // Kick off cards that are already executing right now.
            for (const apply of Array.from(pending)) {
              apply();
              await new Promise((r) => setTimeout(r, 80));
            }
            // Drain: wait for the queue to stay empty for a stable window.
            // CopilotKit will keep activating the next tool call as each
            // resolves; registerPending() will auto-fire them while the
            // flag is on.
            const STABLE_EMPTY_MS = 1500;
            const MAX_TOTAL_MS = 30000;
            const start = Date.now();
            let stableEmptySince: number | null = pending.size === 0 ? Date.now() : null;
            while (Date.now() - start < MAX_TOTAL_MS) {
              await new Promise((r) => setTimeout(r, 200));
              if (pending.size === 0) {
                if (stableEmptySince === null) stableEmptySince = Date.now();
                else if (Date.now() - stableEmptySince > STABLE_EMPTY_MS) break;
              } else {
                stableEmptySince = null;
              }
            }
          } finally {
            autoApplying = false;
            setBusy(false);
          }
        }}
      >
        Apply all
      </Button>
    </div>
  );
};
