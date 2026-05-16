import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react-swc';
import wasm from 'vite-plugin-wasm';
import tailwindcss from '@tailwindcss/vite';
import * as path from 'path';

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react(), wasm(), tailwindcss()],
  build: {
    outDir: path.join(__dirname, 'dist'),
    target: 'esnext',
  },
  resolve: {
    dedupe: ['react', 'react-dom'],
  },
  server: {
    proxy: {
      // ZenRule agent (unauthenticated, hot-reloads JDM files).
      // Evaluate: POST /api/projects/<rule_type>/evaluate/<name>.json
      '/api/projects': {
        target: 'http://localhost:8090',
        changeOrigin: true,
      },
      // atomic-fi Phoenix REST (x-api-key required, attached by axios client).
      '/api/rules': {
        target: 'http://localhost:4100',
        changeOrigin: true,
      },
      '/api/compliance-screenings': {
        target: 'http://localhost:4100',
        changeOrigin: true,
      },
    },
  },
});
