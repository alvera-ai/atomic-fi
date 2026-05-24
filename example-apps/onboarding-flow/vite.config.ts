import react from "@vitejs/plugin-react-swc";
import { componentTagger } from "lovable-tagger";
import path from "path";
import { defineConfig } from "vite";

// Served by Phoenix at /demo/onboarding-flow/ via Plug.Static.
// `vite build --watch` is run by Phoenix's :watchers in dev so file
// changes here regenerate the output; live_reload picks up the
// fresh assets and refreshes the browser tab.
const PHX_STATIC = path.resolve(__dirname, "../../priv/static/demo/onboarding-flow");

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => ({
  base: "/demo/onboarding-flow/",
  build: {
    outDir: PHX_STATIC,
    emptyOutDir: true,
  },
  plugins: [react(), mode === "development" && componentTagger()].filter(Boolean),
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
}));
