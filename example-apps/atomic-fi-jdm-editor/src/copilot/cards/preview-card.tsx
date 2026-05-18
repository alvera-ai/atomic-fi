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
  React.useEffect(() => {
    if (status === 'complete') return;
    return registerPending(onApply);
  }, [status, onApply]);
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
          <Button size="small" icon={<CloseOutlined />} onClick={onReject}>
            Reject
          </Button>
          <Button size="small" type="primary" icon={<CheckOutlined />} onClick={onApply}>
            {applyLabel}
          </Button>
        </div>
      )}
    </Card>
  );
};
