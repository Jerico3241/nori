import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { defineConfig, transformWithEsbuild } from "vite";
import react from "@vitejs/plugin-react";

// Die App wird als webOS-Paket von `file://` geladen. Deshalb relative Pfade
// (`base: "./"`) und keine Annahme über einen Serverstamm.
//
// Übersetzungsziel Chrome 79: das ist die Engine von webOS 6. Damit laufen
// `?.` und `??` auch dort, ohne dass der Quelltext darauf verzichten muss.
/**
 * Aus den Verweisen in `index.html` klassische Skript-Angaben machen.
 *
 * Zwei Änderungen, beide für `file://`:
 *
 * `type="module"` → `defer`. Das Bündel ist ein klassisches Skript, und ein
 * Modul würde von einer `file://`-Seite ohnehin nicht laden (siehe unten bei
 * `format: "iife"`).
 *
 * `crossorigin` weg.
 *
 * Vite setzt es an jedes Skript und jedes Stylesheet. Über HTTP ist das
 * harmlos; von `file://` geladen macht es aus einem gleichartigen Abruf einen
 * mit Herkunftsprüfung — und die scheitert dort, weil eine `file://`-Seite die
 * Herkunft `null` hat. Auf dem Fernseher wäre das ein schwarzer Bildschirm
 * ohne Fehlermeldung.
 *
 * Für den Entwicklungsstand über HTTP ändert das Entfernen nichts: Dateien aus
 * demselben Ursprung brauchen keine Herkunftsprüfung.
 */
function classicScriptTags() {
  return {
    name: "nori-classic-script-tags",
    transformIndexHtml(html: string) {
      return html
        // Das Bündel ist ein klassisches Skript (`format: "iife"`), kein
        // Modul. `defer` statt `type="module"`, weil ein klassisches Skript im
        // Kopf sonst vor dem `<body>` läuft — und `getElementById("root")`
        // dann `null` liefert.
        .replace(/\s+type="module"/g, " defer")
        .replace(/\s+crossorigin(="[^"]*")?/g, "");
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

/**
 * hls.js als eigene Datei neben das Bündel legen.
 *
 * Es wird erst im Player nachgeladen (`src/player/hlsLoader.ts`) und ist nicht
 * Teil des Hauptbündels — beim Start muss der Fernseher es nicht parsen. Die
 * UMD-Fassung aus `node_modules` wird dafür wie das Bündel für Chrome 79
 * übersetzt: Syntax, die webOS 6 nicht kennt, bräche sonst genau den Stream
 * ab, der hls.js braucht.
 *
 * Im Entwicklungsstand liefert der Vite-Server dieselbe Adresse aus.
 */
function vendorHls() {
  const source = resolve(__dirname, "node_modules/hls.js/dist/hls.min.js");
  const target = "vendor/hls.min.js";
  const version = (JSON.parse(readFileSync(resolve(__dirname, "node_modules/hls.js/package.json"), "utf8")) as { version: string }).version;
  return {
    name: "nori-vendor-hls",
    configureServer(server: { middlewares: { use(path: string, handler: (req: unknown, res: { setHeader(k: string, v: string): void; end(body: Buffer): void }) => void): void } }) {
      server.middlewares.use(`/${target}`, (_req, res) => {
        res.setHeader("Content-Type", "text/javascript");
        res.end(readFileSync(source));
      });
    },
    async closeBundle() {
      const lowered = await transformWithEsbuild(readFileSync(source, "utf8"), "hls.min.js", {
        target: "chrome79",
        minify: true,
        legalComments: "none",
      });
      mkdirSync(resolve(__dirname, "dist/vendor"), { recursive: true });
      writeFileSync(
        resolve(__dirname, "dist", target),
        `/*! hls.js ${version} | Apache-2.0 | https://github.com/video-dev/hls.js */\n${lowered.code}`,
      );
    },
  };
}

/** Version und Zeichenfläche aus `appinfo.json` — eine Quelle, keine zweite Zahl im Quelltext. */
const appInfo = JSON.parse(readFileSync(resolve(__dirname, "appinfo.json"), "utf8")) as {
  version: string;
  resolution: string;
};

export default defineConfig(({ command }) => ({
  base: "./",
  /*
   * Die gemeinsame Anwendungsschicht kommt als Quelltext, nicht als gebautes
   * Paket.
   *
   * Der Grund ist React: `shared/nori-app` bringt Kontexte und Haken mit, und
   * die funktionieren nur mit **einer** React-Instanz. Ein über `file:`
   * verknüpftes Paket löst `react` von seinem eigenen Ort aus auf und zöge
   * eine zweite herein — der Fehler, der sich als „Invalid hook call" meldet
   * und stundenlang nach etwas ganz anderem aussieht. Als Quelltext
   * eingebunden gibt es die Frage nicht, und ein Bauschritt weniger gibt es
   * obendrein.
   */
  resolve: {
    alias: {
      "@nori/app": resolve(__dirname, "../../shared/nori-app/src/index.ts"),
    },
    /*
     * Genau eine React-Instanz.
     *
     * `shared/nori-app` hat für seine Typen ein eigenes `react` im
     * `node_modules`. Ohne diese Zeile könnte ein Import aus dem geteilten
     * Quelltext dorthin auflösen — zwei Instanzen, und der Fehler meldet sich
     * als „Invalid hook call" an einer ganz anderen Stelle.
     */
    dedupe: ["react", "react-dom"],
  },
  define: {
    __NORI_WEBOS_VERSION__: JSON.stringify(appInfo.version),
    __NORI_WEBOS_RESOLUTION__: JSON.stringify(appInfo.resolution ?? "1920x1080"),
  },
  plugins: [react(), classicScriptTags(), copyAppInfo(), vendorHls()],
  build: {
    target: ["chrome79"],
    outDir: "dist",
    assetsDir: "assets",
    sourcemap: false,
    chunkSizeWarningLimit: 1600,
    /*
     * Ein klassisches Bündel, kein ES-Modul.
     *
     * Das ist die wichtigste Bauentscheidung dieser Datei. Ein webOS-Paket
     * wird von `file:///usr/palm/applications/tv.nori.app/index.html` geladen,
     * und Chromium lädt von dort **keine** ES-Module: ein
     * `<script type="module" src="./assets/index.js">` scheitert an der
     * Herkunftsprüfung, weil eine `file://`-Seite die Herkunft `null` hat. Auf
     * dem Fernseher bliebe der Bildschirm schwarz — ohne Fehlermeldung, weil
     * das Skript nie läuft, das die Fehler melden würde.
     *
     * `iife` erzeugt stattdessen ein einziges klassisches Skript. Das kostet
     * die aufgeteilten Bündel (React, Spotlight und hls.js liegen dann mit
     * drin), und das ist hier kein Verlust: Die Dateien liegen auf dem Gerät,
     * nicht im Netz — es gibt keine Übertragung, die sich parallelisieren
     * ließe. `modulePreload` entfällt aus demselben Grund.
     */
    modulePreload: false,
    /*
     * Eine CSS-Datei statt CSS im Skript.
     *
     * Bei einem einzigen Bündel legt Vite die Stile sonst **in** das Skript
     * und setzt sie zur Laufzeit. Der Startbildschirm in `index.html` ist aber
     * genau für den Moment davor da: bis das Skript läuft, sähe der Fernseher
     * einen unformatierten Absatz auf Weiß statt des Nori-Symbols auf
     * Fastschwarz.
     */
    cssCodeSplit: false,
    rollupOptions: {
      output: {
        format: "iife",
        inlineDynamicImports: true,
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
