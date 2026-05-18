import React, { useEffect, useState } from 'react';
import { Button } from 'antd';

type ApplyHandle = () => void;

const pending = new Set<ApplyHandle>();
const listeners = new Set<() => void>();

function notify(): void {
  listeners.forEach((fn) => fn());
}

export function registerPending(apply: ApplyHandle): () => void {
  pending.add(apply);
  notify();
  return () => {
    pending.delete(apply);
    notify();
  };
}

export const ApplyAllFooter: React.FC = () => {
  const [count, setCount] = useState(pending.size);
  useEffect(() => {
    const update = (): void => setCount(pending.size);
    listeners.add(update);
    return () => {
      listeners.delete(update);
    };
  }, []);
  if (count < 2) return null;
  return (
    <div className="fixed bottom-20 right-4 px-3 py-2 rounded-md border border-rule bg-surface flex items-center gap-3 z-50 shadow">
      <span className="text-xs text-ink-muted">
        {count} pending action{count === 1 ? '' : 's'}
      </span>
      <Button
        size="small"
        type="primary"
        onClick={async () => {
          const snapshot = Array.from(pending);
          for (const apply of snapshot) {
            apply();
            await new Promise((r) => setTimeout(r, 60));
          }
        }}
      >
        Apply all
      </Button>
    </div>
  );
};
