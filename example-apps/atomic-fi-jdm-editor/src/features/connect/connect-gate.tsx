import React, { useState } from 'react';
import { Alert, Button, Input, Typography } from 'antd';
import { KeyOutlined } from '@ant-design/icons';
import axios from 'axios';
import { connectWithApiKey } from './api-key';
import { errorMessage } from '../../helpers/error-message';

// Startup gate: the editor ships no credentials. The user pastes a
// backend API key, which is verified against GET /api/sessions/verify.
// On success the key is held in sessionStorage for the rest of the
// tab's session and `onConnected` lets the app through.
export const ConnectGate: React.FC<{ onConnected: () => void }> = ({ onConnected }) => {
  const [apiKey, setApiKey] = useState('');
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleConnect = async () => {
    setConnecting(true);
    setError(null);
    try {
      await connectWithApiKey(apiKey);
      onConnected();
    } catch (e) {
      // A rejected key is the common case — name it plainly rather
      // than leaking "Request failed with status code 401".
      const message =
        axios.isAxiosError(e) && e.response?.status === 401
          ? 'That API key was rejected. Check the key and try again.'
          : errorMessage(e);
      setError(message);
      setConnecting(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-surface px-4">
      <div className="w-full max-w-md rounded-lg border border-rule bg-surface-sub p-8">
        <div className="mb-5 flex items-center gap-3">
          <span className="flex h-9 w-9 items-center justify-center rounded-md bg-accent-soft">
            <KeyOutlined style={{ color: 'var(--accent)' }} />
          </span>
          <div>
            <h1 className="font-display text-lg tracking-tight m-0 text-ink">Connect to atomic-fi</h1>
            <span className="text-xs text-ink-muted">JDM rule editor + copilot</span>
          </div>
        </div>

        <Typography.Paragraph type="secondary" style={{ fontSize: 13 }}>
          Enter a backend API key to open the rule editor. The key is kept only for this browser tab and is never
          bundled into the app.
        </Typography.Paragraph>

        <form
          onSubmit={(e) => {
            e.preventDefault();
            if (!connecting && apiKey.trim()) handleConnect();
          }}
        >
          <Input.Password
            id="api-key"
            placeholder="Backend API key"
            autoComplete="off"
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            disabled={connecting}
            size="large"
          />

          {error && <Alert className="mt-3" type="error" showIcon message={error} />}

          <Button
            id="connect-button"
            htmlType="submit"
            type="primary"
            size="large"
            block
            className="mt-4"
            loading={connecting}
            disabled={!apiKey.trim()}
          >
            Connect
          </Button>
        </form>
      </div>
    </div>
  );
};
