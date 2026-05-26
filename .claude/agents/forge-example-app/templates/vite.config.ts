import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import wasm from "vite-plugin-wasm";
import tailwindcss from "@tailwindcss/vite";
import * as path from "path";

// Served by Phoenix at /demo/__SLUG__/ via Plug.Static.
const PHX_STATIC = path.resolve(__dirname, "../../priv/static/demo/__SLUG__");

// Dev-server proxies so the same relative URLs (/api/...) work whether the
// app is served by Phoenix (production / mix phx.server) or by vite directly
// (npm run dev). For env-var overrides, see src/lib/copilot.ts and
// src/lib/zenrule.ts.
const PHOENIX = "http://localhost:4100";
const COPILOT = "http://localhost:4242";
const ZENRULE = "http://localhost:8090";

export default defineConfig({
  base: "/demo/__SLUG__/",
  plugins: [react(), wasm(), tailwindcss()],
  build: {
    outDir: PHX_STATIC,
    emptyOutDir: true,
    target: "esnext",
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
    dedupe: ["react", "react-dom"],
  },
  server: {
    proxy: {
      "/api/copilotkit": { target: COPILOT, changeOrigin: true },
      "/api/projects": { target: ZENRULE, changeOrigin: true },
      "/api": { target: PHOENIX, changeOrigin: true },
    },
  },
});
