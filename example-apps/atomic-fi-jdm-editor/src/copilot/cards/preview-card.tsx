import React from 'react';
import { Button, Card, Tag } from 'antd';
import { CheckOutlined, CloseOutlined } from '@ant-design/icons';

import { registerPending } from './apply-all-footer';

export type PreviewCardProps = {
  title: string;
  status: 'inProgress' | 'executing' | 'complete';
  summary: React.ReactNode;
  diff?: React.ReactNode;
  onApply: () => void;
  onReject: () => void;
  applyLabel?: string;
};

export const PreviewCard: React.FC<PreviewCardProps> = ({
  title,
  status,
  summary,
  diff,
  onApply,
  onReject,
  applyLabel = 'Apply',
}) => {
  const decided = status === 'complete';

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
    if (status !== 'executing' || appliedRef.current) return;
    return registerPending(pendingApply);
  }, [status, pendingApply]);

  return (
    <Card
      size="small"
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
          {status === 'executing' ? (
            <>
              <Button size="small" icon={<CloseOutlined />} onClick={guardedReject}>
                Reject
              </Button>
              <Button size="small" type="primary" icon={<CheckOutlined />} onClick={pendingApply}>
                {applyLabel}
              </Button>
            </>
          ) : (
            <span className="text-xs text-ink-muted self-center">queued — waiting for previous tool to finish…</span>
          )}
        </div>
      )}
    </Card>
  );
};
