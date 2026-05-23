import * as zenWasm from '@gorules/zen-engine-wasm';
import zenWasmUrl from '@gorules/zen-engine-wasm/dist/zen_engine_wasm_bg.wasm?url';

import React from 'react';
import ReactDOM from 'react-dom/client';

import './main.css';

import '@gorules/jdm-editor/dist/style.css';

import 'react-ace';

import 'ace-builds/src-noconflict/ext-language_tools';
import 'ace-builds/src-noconflict/mode-json5';
import 'ace-builds/src-noconflict/mode-liquid';
import 'ace-builds/src-noconflict/mode-javascript';
import 'ace-builds/src-noconflict/mode-typescript';
import 'ace-builds/src-noconflict/snippets/javascript';
import 'ace-builds/src-noconflict/theme-chrome';

import { ThemeContextProvider } from './context/theme.provider.tsx';
import { App } from './app.tsx';
import { AppErrorBoundary } from './components/app-error-boundary.tsx';
import { displayError } from './helpers/error-message.ts';

// Window-level catch-all for errors that React Error Boundaries can't see:
// raw event-handler throws, late `setTimeout` exceptions, unhandled
// promise rejections from helpers that forgot a try/catch. The browser
// would otherwise log to console and the user would see nothing — exactly
// the "I had zero idea the request had failed" failure mode we hit
// during the v2 migration.
//
// Listeners are installed BEFORE `createRoot` so a synchronous render
// error during the first mount still gets toasted (the boundary will
// also catch the same one, but the listener runs first; AntD's
// `message.error` dedupes adjacent identical toasts).
window.addEventListener('error', (event) => {
  // `event.error` is usually the thrown value; fall back to `message`
  // when the runtime didn't attach one (CORS-protected cross-origin
  // scripts, in particular).
  displayError(event.error ?? event.message);
});
window.addEventListener('unhandledrejection', (event) => {
  displayError(event.reason);
});

await zenWasm.default(zenWasmUrl);

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <AppErrorBoundary>
      <ThemeContextProvider>
        <App />
      </ThemeContextProvider>
    </AppErrorBoundary>
  </React.StrictMode>,
);
