import React from 'react';
import { Button, Card, Tag } from 'antd';
import { CheckOutlined, CloseOutlined } from '@ant-design/icons';
import { ToolCallStatus } from '@copilotkit/react-core/v2';

import { registerPending } from './apply-all-footer';

export type PreviewCardProps = {
  title: string;
  status: ToolCallStatus;
  summary: React.ReactNode;
  diff?: React.ReactNode;
  onApply: () => void;
  onReject: () => void;
  applyLabel?: string;
};

// Monotonic per-session counter for HITL card instances. Each PreviewCard
// claims the next integer on mount and keeps it for its lifetime; rendered
// as the `id` suffix on the card + its buttons (`hitl-card-3`,
// `hitl-apply-3`, `hitl-reject-3`). Specs can target by exact id when they
// know the order, or by `data-testid` family (e.g. `hitl-card`) +
// `.filter({hasText:…})` when they don't. The counter resets per page
// load — fine, because a fresh page has no pre-existing cards. Cross-page
// uniqueness isn't a goal; per-session predictability is.
let hitlCardSequence = 0;
const nextCardId = (): number => hitlCardSequence++;

export const PreviewCard: React.FC<PreviewCardProps> = ({
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
  // Claim a session-stable sequence number on mount. `useRef(nextCardId())`
  // runs the initializer once per component instance, so the id stays
  // constant across re-renders (status transitions, prop updates).
  const idxRef = React.useRef(nextCardId());
  const idx = idxRef.current;
  React.useEffect(() => {
    onApplyRef.current = onApply;
  }, [onApply]);
  React.useEffect(() => {
    onRejectRef.current = onReject;
  }, [onReject]);

  const pendingApply = React.useCallback(() => {
    if (appliedRef.current) return;
    appliedRef.current = true;
    onApplyRef.current();
  }, []);
  const guardedReject = React.useCallback(() => {
    if (appliedRef.current) return;
    appliedRef.current = true;
    onRejectRef.current();
  }, []);

  React.useEffect(() => {
    // Only register while truly executable. CK provides respond only in
    // 'executing' for the currently-active tool call; firing in 'inProgress'
    // is a silent no-op that strands the tool call.
    if (status !== ToolCallStatus.Executing || appliedRef.current) return;
    return registerPending(pendingApply);
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
