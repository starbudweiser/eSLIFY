import { defineConfig } from "vite";
import { fileURLToPath } from "node:url";

// Socle est lu directement depuis sa copie locale : une modification des tokens se voit en live.
const SOCLE = "/Volumes/SKYRIM/TOOLS/DESIGN/Socle";

export default defineConfig({
  resolve: { alias: { "@socle": SOCLE } },
  server: {
    port: Number(process.env.PORT) || 5173,
    fs: { allow: [fileURLToPath(new URL(".", import.meta.url)), SOCLE] },
  },
});
