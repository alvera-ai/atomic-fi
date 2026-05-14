import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react-swc';
import wasm from 'vite-plugin-wasm';
import * as path from 'path';

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react(), wasm()],
  build: {
    outDir: path.join(__dirname, 'dist'),
    target: 'esnext',
  },
  resolve: {
    dedupe: ['react', 'react-dom'],
  },
  server: {
    proxy: {
      // Proxies the editor's simulator calls to the ZenRule agent brought up
      // by local-dependencies.yaml. See
      // docs/superpowers/specs/2026-05-13-jdm-editor-scaffold-design.md.
      '/api': {
        target: 'http://localhost:8090',
        changeOrigin: true,
      },
    },
  },
});
