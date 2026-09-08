// Aus dem gebauten Stand ein `.ipk` schnüren.
//
// Ein webOS-Paket ist ein ar-Archiv aus drei Teilen — `debian-binary`,
// `control.tar.gz`, `data.tar.gz` —, und beides, ar und tar, ist hier von Hand
// geschrieben. Das ist Absicht: `ares-package` aus dem LG-SDK erzeugt dasselbe,
// steht aber nicht auf jedem Rechner und in keiner CI zur Verfügung. So läuft
// `npm run webos:package` überall, wo Node läuft, und liefert Byte für Byte
// dasselbe Paket.
//
// Wer das SDK hat, kann weiterhin `ares-package apps/webos/dist` benutzen; das
// Ergebnis ist austauschbar.

import { createHash } from "node:crypto";
import { gzipSync } from "node:zlib";
import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const APP = resolve(HERE, "..");
const DIST = join(APP, "dist");

if (!existsSync(join(DIST, "index.html"))) {
  console.error("[Nori:webOS] dist/index.html fehlt — erst `npm run build`.");
  process.exit(1);
}

const appinfo = JSON.parse(readFileSync(join(APP, "appinfo.json"), "utf8"));
const { id, version } = appinfo;
if (!id || !version) {
  console.error("[Nori:webOS] appinfo.json braucht `id` und `version`.");
  process.exit(1);
}

// ---- tar ------------------------------------------------------------------

/**
 * Ein Eintrag im USTAR-Format.
 *
 * `mtime` ist fest auf 0 gesetzt: ein Paket, das sich bei jedem Bau
 * unterscheidet, lässt sich nicht vergleichen und nicht zwischenspeichern.
 */
function tarHeader(name, size, mode, type) {
  const header = Buffer.alloc(512);
  const write = (value, offset, length) => {
    header.write(value.slice(0, length), offset, "ascii");
  };
  const octal = (value, length) => value.toString(8).padStart(length - 1, "0") + "\0";

  if (Buffer.byteLength(name) > 100) {
    // Über 100 Zeichen teilt USTAR in Präfix und Namen. Nori kommt nicht
    // annähernd dorthin — ein Abbruch ist ehrlicher als ein stilles Kürzen.
    throw new Error(`Pfad zu lang für USTAR: ${name}`);
  }
  write(name, 0, 100);
  write(octal(mode, 8), 100, 8);
  write(octal(0, 8), 108, 8);     // uid
  write(octal(0, 8), 116, 8);     // gid
  write(octal(size, 12), 124, 12);
  write(octal(0, 12), 136, 12);   // mtime
  header.write("        ", 148, 8, "ascii"); // Prüfsumme zunächst als Leerzeichen
  header.write(type, 156, 1, "ascii");
  header.write("ustar\0", 257, 6, "ascii");
  header.write("00", 263, 2, "ascii");
  write("root", 265, 32);
  write("root", 297, 32);

  let sum = 0;
  for (const byte of header) sum += byte;
  header.write(octal(sum, 7), 148, 8, "ascii");
  header.write("\0 ", 154, 2, "ascii");
  return header;
}

function tar(entries) {
  const parts = [];
  for (const entry of entries) {
    if (entry.type === "5") {
      parts.push(tarHeader(entry.name.endsWith("/") ? entry.name : `${entry.name}/`, 0, 0o755, "5"));
      continue;
    }
    parts.push(tarHeader(entry.name, entry.data.length, entry.mode ?? 0o644, "0"));
    parts.push(entry.data);
    const padding = (512 - (entry.data.length % 512)) % 512;
    if (padding > 0) parts.push(Buffer.alloc(padding));
  }
  parts.push(Buffer.alloc(1024)); // zwei leere Blöcke als Ende
  return Buffer.concat(parts);
}

// ---- ar -------------------------------------------------------------------

function arEntry(name, data) {
  const header = Buffer.alloc(60, 0x20);
  header.write(name.padEnd(16).slice(0, 16), 0, "ascii");
  header.write("0".padEnd(12), 16, "ascii");           // mtime
  header.write("0".padEnd(6), 28, "ascii");            // uid
  header.write("0".padEnd(6), 34, "ascii");            // gid
  header.write("100644".padEnd(8), 40, "ascii");       // Modus
  header.write(String(data.length).padEnd(10), 48, "ascii");
  header.write("`\n", 58, "ascii");
  const pad = data.length % 2 === 1 ? Buffer.from("\n") : Buffer.alloc(0);
  return Buffer.concat([header, data, pad]);
}

// ---- Inhalt sammeln --------------------------------------------------------

function collect(dir, base = dir) {
  const out = [];
  for (const name of readdirSync(dir).sort()) {
    const full = join(dir, name);
    const info = statSync(full);
    if (info.isDirectory()) {
      out.push({ dir: relative(base, full).split("\\").join("/") });
      out.push(...collect(full, base));
    } else {
      out.push({
        file: relative(base, full).split("\\").join("/"),
        data: readFileSync(full),
      });
    }
  }
  return out;
}

const contents = collect(DIST);
const appRoot = `usr/palm/applications/${id}`;
const packageRoot = `usr/palm/packages/${id}`;

const dataEntries = [
  { name: "usr", type: "5" },
  { name: "usr/palm", type: "5" },
  { name: "usr/palm/applications", type: "5" },
  { name: appRoot, type: "5" },
];

for (const item of contents) {
  if (item.dir) dataEntries.push({ name: `${appRoot}/${item.dir}`, type: "5" });
}
for (const item of contents) {
  if (item.file) dataEntries.push({ name: `${appRoot}/${item.file}`, data: item.data });
}

// `packageinfo.json` beschreibt das Paket, `appinfo.json` die App darin. webOS
// braucht beides; ohne die erste Datei zeigt der Installationsvorgang keinen
// Namen an.
const packageInfo = Buffer.from(JSON.stringify({
  id,
  version,
  app: id,
  vendor: appinfo.vendor ?? "Nori",
  loc_name: appinfo.title ?? "Nori",
}, null, 2) + "\n");

dataEntries.push(
  { name: "usr/palm/packages", type: "5" },
  { name: packageRoot, type: "5" },
  { name: `${packageRoot}/packageinfo.json`, data: packageInfo },
);

const dataTar = gzipSync(tar(dataEntries), { level: 9 });

const installedSize = contents.reduce((sum, item) => sum + (item.data?.length ?? 0), 0);
const control = Buffer.from([
  `Package: ${id}`,
  `Version: ${version}`,
  "Section: misc",
  "Priority: optional",
  "Architecture: all",
  `Installed-Size: ${installedSize}`,
  `Maintainer: ${appinfo.vendor ?? "Nori"}`,
  `Description: ${appinfo.appDescription ?? "Nori für LG webOS"}`,
  "webOS-Package-Format-Version: 2",
  "webOS-Packager-Version: nori-1.0",
  "",
].join("\n"));

const controlTar = gzipSync(tar([{ name: "control", data: control }]), { level: 9 });

const ipk = Buffer.concat([
  Buffer.from("!<arch>\n"),
  arEntry("debian-binary", Buffer.from("2.0\n")),
  arEntry("control.tar.gz", controlTar),
  arEntry("data.tar.gz", dataTar),
]);

const outName = `${id}_${version}_all.ipk`;
const outPath = join(APP, outName);
writeFileSync(outPath, ipk);

const digest = createHash("sha256").update(ipk).digest("hex");
console.log(`[Nori:webOS] ${outName}`);
console.log(`[Nori:webOS] ${(ipk.length / 1024).toFixed(1)} KB · ${contents.filter((c) => c.file).length} Dateien`);
console.log(`[Nori:webOS] sha256 ${digest}`);
console.log(`[Nori:webOS] ${outPath}`);
