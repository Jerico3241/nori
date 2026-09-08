import { copyFileSync } from "node:fs";
import { resolve } from "node:path";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Die App wird als webOS-Paket von `file://` geladen. Deshalb relative Pfade
// (`base: "./"`) und keine Annahme über einen Serverstamm.
//
// Übersetzungsziel Chrome 79: das ist die Engine von webOS 6. Damit laufen
// `?.` und `??` auch dort, ohne dass der Quelltext darauf verzichten muss.
/**
 * Enact liefert seine Debug-Stile als `.less` mit.
 *
 * Gebraucht wird davon nichts — es ist ein Hilfsraster zum Einfärben von
 * Spotlight-Containern während der Entwicklung. Statt `less` nur dafür als
 * Abhängigkeit aufzunehmen, wird die Datei durch ein leeres Stylesheet
 * ersetzt.
 */
function stubEnactLess() {
  const marker = "\0nori-empty.css";
  return {
    name: "nori-stub-enact-less",
    enforce: "pre" as const,
    resolveId(source: string) {
      return source.endsWith(".less") ? marker : null;
    },
    load(id: string) {
      return id === marker ? "" : null;
    },
  };
}

/**
 * `appinfo.json` gehört neben `package.json`, nicht nach `public/`: es
 * beschreibt das Paket, nicht die Webseite. In den Bauordner muss es trotzdem,
 * weil webOS es dort erwartet.
 */
function copyAppInfo() {
  return {
    name: "nori-copy-appinfo",
    closeBundle() {
      copyFileSync(resolve(__dirname, "appinfo.json"), resolve(__dirname, "dist/appinfo.json"));
    },
  };
}

export default defineConfig(({ command }) => ({
  base: "./",
  plugins: [stubEnactLess(), react(), copyAppInfo()],
  build: {
    target: ["chrome79"],
    outDir: "dist",
    assetsDir: "assets",
    sourcemap: false,
    chunkSizeWarningLimit: 800,
    rollupOptions: {
      output: {
        manualChunks: {
          react: ["react", "react-dom", "react-router-dom"],
          spotlight: ["@enact/spotlight"],
          hls: ["hls.js"],
        },
      },
    },
  },
  server: {
    port: 8731,
    proxy: command === "serve"
      ? {
          // Im Entwicklungsstand liegt der Nori-Server daneben; ohne diese
          // Weiterleitung stünde im Browser die Herkunftsprüfung im Weg.
          "/api": {
            target: process.env.NORI_API ?? "http://127.0.0.1:8730",
            changeOrigin: true,
          },
        }
      : undefined,
  },
}));
