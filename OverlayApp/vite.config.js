import { defineConfig } from "vite";
import { resolve } from "path";

export default defineConfig({
  base: "./",
  build: {
    rollupOptions: {
      input: {
        main: resolve(__dirname, "index.html"),
        mirror: resolve(__dirname, "mirror.html")
      }
    }
  },
  server: {
    host: "127.0.0.1",
    port: 5173
  }
});
