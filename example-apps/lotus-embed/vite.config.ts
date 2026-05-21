import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import * as path from "path";

// Served by Phoenix at /demo/lotus-embed/ via Plug.Static. All HTTP
// from the embed (Lotus dashboard REST + the iframe embed token
// route) goes to Phoenix on the same origin; no dev-server proxies.
const PHX_STATIC = path.resolve(__dirname, "../../priv/static/demo/lotus-embed");

export default defineConfig({
  base: "/demo/lotus-embed/",
  build: {
    outDir: PHX_STATIC,
    emptyOutDir: true,
  },
  plugins: [react()],
});
