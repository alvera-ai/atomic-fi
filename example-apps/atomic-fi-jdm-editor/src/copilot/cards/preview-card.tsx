import React from 'react';
import { Button, Card, Tag } from 'antd';
import { CheckOutlined, CloseOutlined } from '@ant-design/icons';
import { ToolCallStatus } from '@copilotkit/react-core/v2';

import { registerPending } from './apply-all-footer';

export type PreviewCardProps = {
  /**
   * CopilotKit tool-call id (`useHumanInTheLoop` render arg). Stable per
   * tool call across re-renders + branch swaps (e.g. an `add_node` card
   * that flips into the `add_node — duplicate name` branch keeps the same
   * `toolCallId`). Used as the stable suffix on the card + its buttons,
   * so specs can target `#hitl-card-{toolCallId}` and the id won't shift
   * underneath them when the action handler re-renders.
   */
  toolCallId: string;
  title: string;
  status: ToolCallStatus;
  summary: React.ReactNode;
  diff?: React.ReactNode;
  /**
   * Apply / Reject callbacks may return a Promise — the card awaits it
   * before clearing its applied guard. Critical for `respond?.(...)`,
   * which returns a Promise the AG-UI client needs resolved before it
   * composes the next `/run`. Without the await we hit
   * `AI_MissingToolResultsError` on the runtime side (the LLM's next
   * turn sees tool calls without matching results).
   */
  onApply: () => void | Promise<void>;
  onReject: () => void | Promise<void>;
  applyLabel?: string;
};

// Per-session ToolCallId → ordinal map. Each new toolCallId claims the next
// integer on first sighting; subsequent renders with the same toolCallId
// keep their ordinal. Lets specs reach for `#hitl-card-{ordinal}` (e.g.
// `#hitl-card-0` for "first card in this session") when they don't have
// the toolCallId on hand — useful when you just want "the first add_node
// card", regardless of its CopilotKit-assigned uuid.
const toolCallOrdinals = new Map<string, number>();
let nextOrdinal = 0;
export function ordinalFor(toolCallId: string): number {
  const existing = toolCallOrdinals.get(toolCallId);
  if (existing !== undefined) return existing;
  const n = nextOrdinal++;
  toolCallOrdinals.set(toolCallId, n);
  return n;
}

export const PreviewCard: React.FC<PreviewCardProps> = ({
  toolCallId,
  title,
  status,
  summary,
  diff,
  onApply,
  onReject,
  applyLabel = 'Apply',
}) => {
  const decided = status === ToolCallStatus.Complete;

  // Idempotency + stable identity guard.
  //
  // The interesting part: CopilotKit serializes concurrent tool calls of the
  // same action. Only ONE of the agent's add_node × 3 calls is in `executing`
  // at a time — the other two are demoted to `inProgress` with respond
  // = undefined until the active one resolves and CK promotes the next.
  //
  // Therefore we MUST only register in the Apply-all queue (and fire) when
  // status === 'executing'. Firing under `inProgress` calls respond?.() with
  // an undefined respond — a silent no-op — and the tool call stays awaiting
  // forever while the card looks "pending" indefinitely.
  //
  // Stale-respond defense: `onApply` from the action handler closes over the
  // respond function for THIS render. We keep an onApplyRef so the queued
  // handle always calls the latest closure (latest respond) even if React
  // hasn't re-rendered the card recently.
  //
  // Idempotency: `appliedRef` prevents a manual double-click or duplicate
  // Apply-all fire from invoking onApply twice for the same card. Each card
  // has its own component instance and its own ref, so this isolation is
  // per-tool-call (which is what we want).
  const appliedRef = React.useRef(false);
  const onApplyRef = React.useRef(onApply);
  const onRejectRef = React.useRef(onReject);
  // Holds the active `registerPending` deregister token, set by the
  // useEffect below whenever this card is in the Apply-all queue. After
  // the user (or apply-all) fires the card, `pendingApply` / `guardedReject`
  // calls this immediately so the footer's pending counter drops in
  // real time. Without this, the useEffect cleanup only ran on
  // deps change (status / pendingApply) — neither changes on click, so
  // the card stayed in the registry indefinitely and the footer showed
  // a stale "N pending actions" badge for already-applied cards.
  const deregisterRef = React.useRef<(() => void) | null>(null);
  // Ordinal is keyed on toolCallId, so remounts (status-branch swaps,
  // unmount during streaming, etc.) reuse the same number. The id stays
  // stable for the lifetime of the tool call, not just the React node.
  const idx = ordinalFor(toolCallId);
  React.useEffect(() => {
    onApplyRef.current = onApply;
  }, [onApply]);
  React.useEffect(() => {
    onRejectRef.current = onReject;
  }, [onReject]);

  const pendingApply = React.useCallback(async () => {
    if (appliedRef.current) return;
    appliedRef.current = true;
    // Unregister from the Apply-all queue immediately. The useEffect
    // cleanup only fires on deps change; status/pendingApply don't change
    // on click, so without this the card would stay in the registry and
    // the footer's "N pending actions" badge would stay stale.
    deregisterRef.current?.();
    deregisterRef.current = null;
    // Await so callers that wrap `respond?.()` get its Promise resolved
    // before we hand control back — see `onApply` prop doc above.
    await onApplyRef.current();
  }, []);
  const guardedReject = React.useCallback(async () => {
    if (appliedRef.current) return;
    appliedRef.current = true;
    deregisterRef.current?.();
    deregisterRef.current = null;
    await onRejectRef.current();
  }, []);

  React.useEffect(() => {
    // Only register while truly executable. CK provides respond only in
    // 'executing' for the currently-active tool call; firing in 'inProgress'
    // is a silent no-op that strands the tool call.
    if (status !== ToolCallStatus.Executing || appliedRef.current) return;
    const unregister = registerPending(pendingApply);
    deregisterRef.current = unregister;
    return () => {
      unregister();
      // Don't null out deregisterRef here — if we re-register on the next
      // run, the new effect overwrites it. Nulling on click is what
      // matters; this branch is just the deps-change cleanup.
    };
  }, [status, pendingApply]);

  // Stable hooks for E2E specs. Hybrid scheme:
  //   * `data-testid="hitl-card"` (and same on the buttons) — testid family
  //     for `getByTestId(...).nth(i)` and `.filter({hasText:...})` lookups.
  //     Idiomatic for repeated patterns where multiple cards share semantics.
  //   * `id="hitl-card-{n}"` (and matching on the buttons) — session-stable
  //     suffixed id so specs targeting a known-position card can use plain
  //     `#hitl-card-2` instead of nth().
  //   * `data-hitl-title` + `data-hitl-status` — filter attributes for
  //     scenario-based selectors (e.g. "the executing add_node card").
  const cardStatus =
    status === ToolCallStatus.Complete
      ? 'resolved'
      : status === ToolCallStatus.Executing
        ? 'executing'
        : 'queued';

  return (
    <Card
      size="small"
      id={`hitl-card-${idx}`}
      data-testid="hitl-card"
      data-hitl-title={title}
      data-hitl-status={cardStatus}
      title={
        <div className="flex items-center gap-2">
          <span className="font-mono text-[12px]">{title}</span>
          {decided ? <Tag color="default">resolved</Tag> : <Tag color="processing">pending</Tag>}
        </div>
      }
      styles={{ body: { padding: 12 } }}
      className="my-2"
    >
      <div className="text-sm">{summary}</div>
      {diff && <div className="mt-2 font-mono text-[12px] whitespace-pre-wrap">{diff}</div>}
      {!decided && (
        <div className="flex justify-end gap-2 mt-3">
          {status === ToolCallStatus.Executing ? (
            <>
              <Button
                id={`hitl-reject-${idx}`}
                data-testid="hitl-reject"
                size="small"
                icon={<CloseOutlined />}
                onClick={guardedReject}
              >
                Reject
              </Button>
              <Button
                id={`hitl-apply-${idx}`}
                data-testid="hitl-apply"
                size="small"
                type="primary"
                icon={<CheckOutlined />}
                onClick={pendingApply}
              >
                {applyLabel}
              </Button>
            </>
          ) : (
            <span
              id={`hitl-queued-${idx}`}
              data-testid="hitl-queued"
              className="text-xs text-ink-muted self-center"
            >
              queued — waiting for previous tool to finish…
            </span>
          )}
        </div>
      )}
    </Card>
  );
};
