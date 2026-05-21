import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react-swc';
import wasm from 'vite-plugin-wasm';
import tailwindcss from '@tailwindcss/vite';
import * as path from 'path';

// Served by Phoenix at /demo/atomic-fi-jdm-editor/ via Plug.Static.
// All HTTP from the editor (REST API + /api/copilotkit + ZenRule via
// Phoenix proxy) goes to Phoenix on the same origin; no dev-server
// proxies needed.
const PHX_STATIC = path.resolve(__dirname, '../../priv/static/demo/atomic-fi-jdm-editor');

// https://vitejs.dev/config/
export default defineConfig({
  base: '/demo/atomic-fi-jdm-editor/',
  plugins: [react(), wasm(), tailwindcss()],
  build: {
    outDir: PHX_STATIC,
    emptyOutDir: true,
    target: 'esnext',
  },
  resolve: {
    dedupe: ['react', 'react-dom'],
  },
});
