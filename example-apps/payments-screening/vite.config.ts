import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'node:path'

// The app talks to the atomic-fi API. Browsers block cross-origin requests to
// the Phoenix API (it sends no CORS headers), so in dev we proxy same-origin
// `/api/*` to the running server. Override the target with VITE_API_PROXY to
// point the dev server at a different deployment.
const API_PROXY = process.env.VITE_API_PROXY ?? 'http://localhost:4100'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { '@': path.resolve(__dirname, './src') },
  },
  server: {
    port: 4200,
    proxy: {
      '/api': { target: API_PROXY, changeOrigin: true },
    },
  },
})
