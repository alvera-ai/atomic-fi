import React from 'react';
import { Button, Result } from 'antd';

import { displayError, errorMessage } from '../helpers/error-message';

// React-blessed catch-all for render/lifecycle/constructor errors anywhere
// in the tree below this boundary (https://react.dev/reference/react/Component#catching-rendering-errors).
//
// Coverage map for the editor's surface area:
//   • Render/lifecycle/constructor exceptions in any child component
//     → caught here, toast + fallback UI.
//   • CopilotKit RUN_ERROR / agent / runtime errors
//     → already caught by `<CopilotKitProvider onError>`
//       (`src/copilot/copilot-provider.tsx`).
//   • Async errors that escape try/catch (event handlers throwing into a
//     promise, unhandled rejections, late `setTimeout` throws)
//     → caught by the window-level `error` / `unhandledrejection`
//       listeners installed in `main.tsx`.
//   • Explicit awaits in our own helpers (rules-api, simulator, save flow)
//     → already wrap with try/catch + `displayError(e)`.
//
// Together those four converge on one notifier — AntD `message.error` via
// `displayError(e)` — so the user never sees the silent-failure state we
// hit during the v2 migration ("I had zero idea the request had failed").
//
// Error boundaries can only be class components — there is no hook
// equivalent in React 18 (and likely none in 19).
interface AppErrorBoundaryProps {
  children: React.ReactNode;
}

interface AppErrorBoundaryState {
  hasError: boolean;
  message: string;
}

export class AppErrorBoundary extends React.Component<AppErrorBoundaryProps, AppErrorBoundaryState> {
  public state: AppErrorBoundaryState = { hasError: false, message: '' };

  public static getDerivedStateFromError(error: unknown): AppErrorBoundaryState {
    // Runs during the render that errored — must return synchronously and
    // must not have side effects. Just records the failure so the next
    // render shows the fallback.
    return { hasError: true, message: errorMessage(error) };
  }

  public componentDidCatch(error: unknown, info: React.ErrorInfo): void {
    // Runs after the fallback render — side effects (toast + console) go
    // here. The toast surfaces the failure to the user; the console log
    // keeps the component stack alongside the message for diagnosis.
    displayError(error);
    // eslint-disable-next-line no-console -- error boundary needs a console trail beyond the toast
    console.error('AppErrorBoundary caught:', error, info.componentStack);
  }

  public render(): React.ReactNode {
    if (this.state.hasError) {
      // Deliberately not auto-recovering — we don't know what state the
      // tree is in. A full reload is the safest reset; the user gets to
      // decide when to retry.
      return (
        <Result
          status="error"
          title="Something went wrong"
          subTitle={this.state.message}
          extra={[
            <Button key="reload" type="primary" onClick={() => window.location.reload()}>
              Reload
            </Button>,
          ]}
        />
      );
    }
    return this.props.children;
  }
}
