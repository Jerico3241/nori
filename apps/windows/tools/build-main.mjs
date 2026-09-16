// Hauptprozess und Brücke bündeln.
//
// Warum gebündelt und nicht als lose Dateien: `electron-builder` müsste sonst
// `node_modules` mit ins Paket nehmen — für `linkedom` und den Kern wären das
// ein paar hundert Dateien, die beim Start einzeln von der Platte gelesen
// werden. Ein Bündel ist eine Datei und startet messbar schneller.
//
// CommonJS, nicht ESM: Electron lädt `preload` nur als CommonJS, und der
// Hauptprozess bleibt aus demselben Grund beim selben Format — zwei Formate in
// einem Paket sind eine Fehlerquelle ohne Gegenwert.
//
// Die Google-Zugangsdaten kommen beim Bauen aus der Umgebung und werden fest
// eingesetzt. Eingecheckt wird keines; ohne sie entsteht ein Paket ohne
// Abgleich, und die Oberfläche sagt das in einem Satz.

import { build } from "esbuild";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const APP = resolve(HERE, "..");
const pkg = JSON.parse(readFileSync(resolve(APP, "package.json"), "utf8"));

const credentials = {
  __NORI_GOOGLE_CLIENT_ID__: JSON.stringify(process.env.NORI_GOOGLE_DESKTOP_CLIENT_ID ?? ""),
  __NORI_GOOGLE_CLIENT_SECRET__: JSON.stringify(process.env.NORI_GOOGLE_DESKTOP_CLIENT_SECRET ?? ""),
  __NORI_APP_VERSION__: JSON.stringify(pkg.version),
};

async function bundle(entry, outfile, platform = "node") {
  await build({
    entryPoints: [resolve(APP, entry)],
    outfile: resolve(APP, outfile),
    bundle: true,
    platform,
    format: "cjs",
    // Electron 38 fährt Node 22.
    target: "node22",
    sourcemap: false,
    minify: false,
    external: ["electron"],
    define: credentials,
    logLevel: "warning",
  });
}

await bundle("src/main/main.ts", "dist-main/main.cjs");
await bundle("src/main/preload.ts", "dist-main/preload.cjs");

const id = process.env.NORI_GOOGLE_DESKTOP_CLIENT_ID ?? "";
console.log(`[Nori:Windows] Hauptprozess gebaut · Google-Zugang: ${id ? "konfiguriert" : "nicht konfiguriert"}`);
