import { copyFileSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Die Oberfläche wird im Paket von `file://` geladen — wie auf dem Fernseher.
// Deshalb relative Pfade und keine Annahme über einen Serverstamm.
//
// Anders als beim Fernseher darf es hier ein **ES-Modul** sein: Electron lädt
// die Seite über `loadFile`, und Chromium erlaubt Module von `file://`, wenn
// sie aus demselben Verzeichnis kommen. Damit bleiben Code-Splitting und
// `modulePreload` erhalten, und die Startseite wartet nicht auf den Player.

const pkg = JSON.parse(readFileSync(resolve(__dirname, "package.json"), "utf8")) as { version: string };

/** Das App-Symbol neben die Oberfläche legen — Seitenleiste und Startbild zeigen es. */
function copyIcon() {
  return {
    name: "nori-copy-icon",
    closeBundle() {
      copyFileSync(resolve(__dirname, "build/icon.png"), resolve(__dirname, "dist/icon.png"));
    },
  };
}

export default defineConfig({
  base: "./",
  define: {
    __NORI_APP_VERSION__: JSON.stringify(pkg.version),
  },
  plugins: [react(), copyIcon()],
  resolve: {
    alias: {
      // Die gemeinsame Anwendungsschicht kommt als Quelltext, nicht als
      // gebautes Paket — siehe die ausführliche Begründung in
      // `apps/webos/vite.config.ts`.
      "@nori/app": resolve(__dirname, "../../shared/nori-app/src/index.ts"),
    },
    /*
     * Genau eine Instanz — und zwar die dieser App.
     *
     * `shared/nori-app` wird als **Quelltext** eingebunden und bringt selbst
     * kein `node_modules` mit. Ohne diese Liste suchte Vite `@nori/core`,
     * `react` und `hls.js` neben der Quelldatei, also unter
     * `shared/nori-app/node_modules` — das es in einer frischen Arbeitskopie
     * nicht gibt. In der CI scheiterte genau daran der Lauf `Build webOS`.
     *
     * Bei React ist es zusätzlich eine Frage der Richtigkeit: zwei Instanzen
     * melden sich als „Invalid hook call" an ganz anderer Stelle.
     */
    dedupe: ["react", "react-dom", "@nori/core", "hls.js"],
  },
  build: {
    // Electron 38 fährt Chromium 140 — hier gibt es keinen Grund, alt zu
    // übersetzen. Das spart Bündelgröße und Startzeit.
    target: "chrome130",
    outDir: "dist",
    assetsDir: "assets",
    sourcemap: false,
    chunkSizeWarningLimit: 1200,
    rollupOptions: {
      output: {
        /*
         * Drei Bündel statt einem.
         *
         * React und hls.js ändern sich selten und liegen getrennt; der
         * Player-Code kommt ohnehin über einen dynamischen Import erst dann,
         * wenn jemand etwas abspielt. Auf einer lokalen Platte spart das keine
         * Übertragung, aber Parse- und Kompilierzeit beim Start — und die ist
         * auf einem schwachen Rechner der Unterschied.
         */
        manualChunks: {
          react: ["react", "react-dom", "react-router-dom"],
        },
      },
    },
  },
  server: {
    port: 8741,
  },
});
