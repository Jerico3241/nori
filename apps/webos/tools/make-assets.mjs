// Symbole und Startbild für das webOS-Paket erzeugen.
//
// Eigene Grafik, kein fremdes Material: das „N" von Nori auf dem dunklen Grund
// der App, mit dem Nori-Orange als Verlauf. Geschrieben werden echte PNG-
// Dateien — webOS zeigt in der Kachelübersicht kein SVG.
//
// Der Encoder unten ist absichtlich handgeschrieben (zlib aus node:zlib, sonst
// nichts): eine Bildbibliothek als Abhängigkeit nur für vier Symbole wäre für
// dieses Projekt zu viel, und der Build soll ohne Netz durchlaufen.

import { deflateSync } from "node:zlib";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const PUBLIC = join(HERE, "..", "public");

const BG = [0x05, 0x06, 0x0a];
const ACCENT_TOP = [0xf4, 0x75, 0x21];
const ACCENT_BOTTOM = [0xc1, 0x49, 0x0d];

/** Ein 32-Bit-CRC nach der PNG-Spezifikation. */
const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(buffer) {
  let c = 0xffffffff;
  for (const byte of buffer) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

/** `pixels` ist RGB, drei Bytes je Punkt, zeilenweise. */
function encodePNG(width, height, pixels) {
  const stride = width * 3;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y += 1) {
    raw[y * (stride + 1)] = 0; // Filter „none"
    pixels.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;  // Bittiefe
  ihdr[9] = 2;  // Farbtyp: Truecolor
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

function blend(base, over, alpha) {
  return [
    Math.round(base[0] + (over[0] - base[0]) * alpha),
    Math.round(base[1] + (over[1] - base[1]) * alpha),
    Math.round(base[2] + (over[2] - base[2]) * alpha),
  ];
}

/**
 * Deckung des Buchstabens „N" an einem Punkt.
 *
 * Der Buchstabe steht als drei Balken (links, rechts, Diagonale) in
 * Einheitskoordinaten, damit er in jeder Größe gleich aussieht. Die weichen
 * Kanten kommen aus der Distanz zum Balken, nicht aus einer Glättung im
 * Nachhinein — das bleibt auch bei 80 px sauber.
 */
function letterAlpha(u, v) {
  const w = 0.155;             // Balkenbreite
  const top = 0.16;
  const bottom = 0.84;
  if (v < top - 0.02 || v > bottom + 0.02) return 0;
  const edge = (d) => Math.max(0, Math.min(1, (0.018 - d) / 0.018));

  const vClamped = Math.max(top, Math.min(bottom, v));
  const capV = (d) => (v < top ? Math.max(d, top - v) : v > bottom ? Math.max(d, v - bottom) : d);

  // Linker und rechter Balken.
  const left = capV(Math.abs(u - (0.26 + w / 2)) - w / 2);
  const right = capV(Math.abs(u - (0.74 - w / 2)) - w / 2);

  // Diagonale von links oben nach rechts unten.
  const t = (vClamped - top) / (bottom - top);
  const centre = 0.26 + w / 2 + t * (0.74 - w / 2 - (0.26 + w / 2));
  const diagonal = capV(Math.abs(u - centre) - w / 2 * 1.18);

  return Math.max(edge(left), edge(right), edge(diagonal));
}

function renderIcon(size) {
  const pixels = Buffer.alloc(size * size * 3);
  const radius = size * 0.22;
  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      const u = (x + 0.5) / size;
      const v = (y + 0.5) / size;

      // Abgerundetes Quadrat: außerhalb bleibt der App-Grund stehen.
      const dx = Math.max(radius - x, 0, x - (size - radius));
      const dy = Math.max(radius - y, 0, y - (size - radius));
      const corner = Math.sqrt(dx * dx + dy * dy);
      const inside = Math.max(0, Math.min(1, (radius - corner) / Math.max(1, size * 0.01) + 1));

      const plate = blend(ACCENT_BOTTOM, ACCENT_TOP, 1 - v * 0.85);
      const letter = letterAlpha(u, v);
      const face = blend(plate, [0x14, 0x08, 0x02], letter);
      const [r, g, b] = blend(BG, face, inside);
      const index = (y * size + x) * 3;
      pixels[index] = r;
      pixels[index + 1] = g;
      pixels[index + 2] = b;
    }
  }
  return encodePNG(size, size, pixels);
}

function renderSplash(width, height) {
  const pixels = Buffer.alloc(width * height * 3);
  const cx = width / 2;
  const cy = height * 0.44;
  const glow = width * 0.42;
  const mark = Math.round(height * 0.19);
  const markX = Math.round(cx - mark / 2);
  const markY = Math.round(cy - mark / 2);
  const icon = { size: mark };

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const dist = Math.hypot(x - cx, y - cy);
      const halo = Math.max(0, 1 - dist / glow) ** 2 * 0.14;
      let [r, g, b] = blend(BG, ACCENT_TOP, halo);

      const lx = x - markX;
      const ly = y - markY;
      if (lx >= 0 && ly >= 0 && lx < icon.size && ly < icon.size) {
        const u = (lx + 0.5) / icon.size;
        const v = (ly + 0.5) / icon.size;
        const radius = icon.size * 0.22;
        const dx = Math.max(radius - lx, 0, lx - (icon.size - radius));
        const dy = Math.max(radius - ly, 0, ly - (icon.size - radius));
        const corner = Math.sqrt(dx * dx + dy * dy);
        const inside = Math.max(0, Math.min(1, (radius - corner) / Math.max(1, icon.size * 0.01) + 1));
        const plate = blend(ACCENT_BOTTOM, ACCENT_TOP, 1 - v * 0.85);
        const face = blend(plate, [0x14, 0x08, 0x02], letterAlpha(u, v));
        [r, g, b] = blend([r, g, b], face, inside);
      }

      const index = (y * width + x) * 3;
      pixels[index] = r;
      pixels[index + 1] = g;
      pixels[index + 2] = b;
    }
  }
  return encodePNG(width, height, pixels);
}

mkdirSync(PUBLIC, { recursive: true });

const files = [
  ["icon-80.png", renderIcon(80)],
  ["icon-130.png", renderIcon(130)],
  ["icon-400.png", renderIcon(400)],
  ["splash-1920x1080.png", renderSplash(1920, 1080)],
];

for (const [name, data] of files) {
  writeFileSync(join(PUBLIC, name), data);
  console.log(`[Nori:webOS] ${name} — ${(data.length / 1024).toFixed(1)} KB`);
}
