import React, { useState } from 'react';
import { Button, Card, Input, Tag } from 'antd';
import { DeleteOutlined, CloseOutlined } from '@ant-design/icons';

export type DestructiveCardProps = {
  title: string;
  status: 'inProgress' | 'executing' | 'complete';
  filename: string;
  warning: React.ReactNode;
  onApply: () => void;
  onReject: () => void;
};

export const DestructiveCard: React.FC<DestructiveCardProps> = ({
  title,
  status,
  filename,
  warning,
  onApply,
  onReject,
}) => {
  const [confirmText, setConfirmText] = useState('');
  const decided = status === 'complete';
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
  return (
    <Card
      size="small"
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
      {!decided && status === 'executing' && (
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
          />
          <div className="flex justify-end gap-2 mt-3">
            <Button size="small" icon={<CloseOutlined />} onClick={guardedReject}>
              Cancel
            </Button>
            <Button size="small" danger type="primary" icon={<DeleteOutlined />} disabled={!ready} onClick={guardedApply}>
              Delete
            </Button>
          </div>
        </>
      )}
      {!decided && status !== 'executing' && (
        <div className="mt-2 text-xs text-ink-muted">queued — waiting for previous tool to finish…</div>
      )}
    </Card>
  );
};
