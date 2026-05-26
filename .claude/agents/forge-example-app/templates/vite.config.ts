import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import * as path from "path";

const PHX_STATIC = path.resolve(__dirname, "../../priv/static/demo/__SLUG__");

export default defineConfig({
  base: "/demo/__SLUG__/",
  build: {
    outDir: PHX_STATIC,
    emptyOutDir: true,
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  plugins: [react(), tailwindcss()],
});
