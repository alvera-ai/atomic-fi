import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'node:path'

// Served by Phoenix at /demo/payments-screening/ via Plug.Static — in prod
// (Dockerfile build) and in dev (the :watchers `vite build --watch` in
// config/dev.exs). There it is same-origin with the API, so no proxy is needed.
// The dev-server proxy below is only for running this app standalone
// (`pnpm --filter payments-screening dev` on :4200): browsers block cross-origin
// calls to the Phoenix API (it sends no CORS headers), so the dev server proxies
// same-origin `/api/*` to it. Override the target with VITE_API_PROXY.
const PHX_STATIC = path.resolve(__dirname, '../../priv/static/demo/payments-screening')
const API_PROXY = process.env.VITE_API_PROXY ?? 'http://localhost:4100'

export default defineConfig({
  base: '/demo/payments-screening/',
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  build: {
    outDir: PHX_STATIC,
    emptyOutDir: true,
  },
  server: {
    port: 4200,
    proxy: {
      '/api': { target: API_PROXY, changeOrigin: true },
    },
  },
})
