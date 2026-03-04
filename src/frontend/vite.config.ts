import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import tailwindcss from "@tailwindcss/vite";
import { resolve } from "node:path";

export default defineConfig({
  plugins: [vue(), tailwindcss()],
  resolve: {
    alias: {
      "@": resolve(__dirname, "src"),
    },
  },
  server: {
    port: 5174,
    proxy: {
      "/api": {
        target: "http://localhost:3900",
        changeOrigin: true,
      },
      "/health": {
        target: "http://localhost:3900",
        changeOrigin: true,
      },
      "/ws": {
        target: "ws://localhost:3900",
        ws: true,
      },
    },
  },
});
