import React, { useState } from 'react';
import { Button, Card, Input, Tag } from 'antd';
import { DeleteOutlined, CloseOutlined } from '@ant-design/icons';
import { ToolCallStatus } from '@copilotkit/react-core/v2';

import { ordinalFor } from './preview-card';

export type DestructiveCardProps = {
  /** CopilotKit tool-call id — same role as in PreviewCard. */
  toolCallId: string;
  title: string;
  status: ToolCallStatus;
  filename: string;
  warning: React.ReactNode;
  onApply: () => void;
  onReject: () => void;
};

export const DestructiveCard: React.FC<DestructiveCardProps> = ({
  toolCallId,
  title,
  status,
  filename,
  warning,
  onApply,
  onReject,
}) => {
  const [confirmText, setConfirmText] = useState('');
  const decided = status === ToolCallStatus.Complete;
  const ready = confirmText.trim() === filename;

  // Same idempotency + stale-respond defense as PreviewCard. See that file
  // for the full explanation of CK's per-action serialization.
  const appliedRef = React.useRef(false);
  const onApplyRef = React.useRef(onApply);
  const onRejectRef = React.useRef(onReject);
  React.useEffect(() => {
    onApplyRef.current = onApply;
  }, [onApply]);
  React.useEffect(() => {
    onRejectRef.current = onReject;
  }, [onReject]);
  const guardedApply = React.useCallback(() => {
    if (appliedRef.current) return;
    appliedRef.current = true;
    onApplyRef.current();
  }, []);
  const guardedReject = React.useCallback(() => {
    if (appliedRef.current) return;
    appliedRef.current = true;
    onRejectRef.current();
  }, []);
  const idx = ordinalFor(toolCallId);
  return (
    <Card
      size="small"
      id={`hitl-card-${idx}`}
      data-testid="hitl-card"
      data-hitl-title={title}
      data-hitl-status={decided ? 'resolved' : status === ToolCallStatus.Executing ? 'executing' : 'queued'}
      data-hitl-kind="destructive"
      title={
        <div className="flex items-center gap-2">
          <span className="font-mono text-[12px]">{title}</span>
          <Tag color={decided ? 'default' : 'error'}>{decided ? 'resolved' : 'destructive'}</Tag>
        </div>
      }
      styles={{ body: { padding: 12 } }}
      style={{ borderColor: decided ? undefined : '#ff4d4f' }}
      className="my-2"
    >
      <div className="text-sm">{warning}</div>
      {!decided && status === ToolCallStatus.Executing && (
        <>
          <div className="mt-2 text-xs">
            Type <code className="font-mono">{filename}</code> to confirm:
          </div>
          <Input
            size="small"
            className="mt-1"
            value={confirmText}
            onChange={(e) => setConfirmText(e.target.value)}
            placeholder={filename}
            id={`hitl-confirm-${idx}`}
            data-testid="hitl-confirm"
          />
          <div className="flex justify-end gap-2 mt-3">
            <Button
              id={`hitl-reject-${idx}`}
              data-testid="hitl-reject"
              size="small"
              icon={<CloseOutlined />}
              onClick={guardedReject}
            >
              Cancel
            </Button>
            <Button
              id={`hitl-apply-${idx}`}
              data-testid="hitl-apply"
              size="small"
              danger
              type="primary"
              icon={<DeleteOutlined />}
              disabled={!ready}
              onClick={guardedApply}
            >
              Delete
            </Button>
          </div>
        </>
      )}
      {!decided && status !== ToolCallStatus.Executing && (
        <div
          id={`hitl-queued-${idx}`}
          data-testid="hitl-queued"
          className="mt-2 text-xs text-ink-muted"
        >
          queued — waiting for previous tool to finish…
        </div>
      )}
    </Card>
  );
};
