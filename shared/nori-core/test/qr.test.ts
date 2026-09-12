// Der QR-Code für den Gerätefluss auf dem Fernseher.
//
// ## Warum hier Festwerte stehen
//
// Ein Encoder, der nur gegen seine eigenen Regeln geprüft ist, beweist nichts:
// ein falsch gesetztes Muster wäre in Prüfung und Umsetzung gleich falsch, und
// der Code liesse sich trotzdem nicht scannen. Ein QR-Code ist ausserdem kein
// Format, bei dem „sieht plausibel aus" etwas heisst.
//
// Die Matrizen unten stammen deshalb **nicht** von diesem Encoder, sondern von
// einer unabhängigen Referenzumsetzung (Nayukis `qrcodegen`, Fassungen 1 bis 10,
// Fehlerkorrektur M, Byte-Modus). Sie sind Modul für Modul übernommen. Wer den
// Encoder ändert und einen dieser Tests rot sieht, hat den Code kaputt gemacht
// — nicht den Test.
//
// Geprüft wurde die Umsetzung zusätzlich über alle Längen von 1 bis 213 Byte
// gegen dieselbe Referenz; hier stehen die Fälle, die Nori wirklich anzeigt,
// plus einer über Fassung 7, weil erst dort das Fassungsfeld hinzukommt.
//
// Einen zweiten Encoder in Swift gibt es absichtlich nicht: den QR-Code
// braucht nur der Fernseher. iPhone und Mac öffnen den Browser.

import assert from "node:assert/strict";
import test from "node:test";
import { encodeQrCode, qrSvgPath, QrError } from "../src/qr.js";
import { deviceQrPayload } from "../src/google/auth.js";

/** `modules` als Zeilenfolge, damit ein Unterschied lesbar ist. */
function rows(text: string): string[] {
  const code = encodeQrCode(text);
  return code.modules.map((row) => row.map((dark) => (dark ? "#" : ".")).join(""));
}

/** Fassung 3, Maske 3 — 29 × 29 Module. */
const DEVICE_TEXT = "https://www.google.com/device";
const DEVICE_ROWS = [
  "#######.##..#..#####..#######",
  "#.....#.####..##..#...#.....#",
  "#.###.#..#######..###.#.###.#",
  "#.###.#.#.#.#...##.#..#.###.#",
  "#.###.#...####...#.#..#.###.#",
  "#.....#..##...#...###.#.....#",
  "#######.#.#.#.#.#.#.#.#######",
  "........#.#..##..#.#.........",
  "#.##.###.#.#.##.###...#..#.##",
  "###.....##.##..##.#######...#",
  "##.##.#.#.##..##.##..#.##.##.",
  "#####..##.#..###..#..#.##...#",
  "......#.#..##...##.......##..",
  "...#........##...###..##..###",
  "...#####..#.#.#..###.#.##.###",
  "#....#.#....##.#..###.###..#.",
  "##..#.#.###.#.....####..##.#.",
  ".#..#.....##.#...#.....#.###.",
  "#.....#..####.....#.#.##..#..",
  "..##.#.#...#...####..##...#..",
  ".##.###.#.#.##.#.##########..",
  "........##.#.###..#.#...#####",
  "#######.#.##.#..#..##.#.##.#.",
  "#.....#.#####...#.#.#...##.##",
  "#.###.#..#....##.#..#####.#.#",
  "#.###.#.##.####.##..##..##.#.",
  "#.###.#.####.####.#.#..#..#.#",
  "#.....#......#..#...#..#.#.#.",
  "#######.###.#..#.#.####..#.#.",
];

/** Fassung 4, Maske 2 — 33 × 33 Module. */
const DEVICEMITCODE_TEXT = "https://www.google.com/device?user_code=WDXR-KQPF";
const DEVICEMITCODE_ROWS = [
  "#######..#....#...###..#..#######",
  "#.....#...#....##.#.###...#.....#",
  "#.###.#.#...#.###..#####..#.###.#",
  "#.###.#.##.#...#..##.##.#.#.###.#",
  "#.###.#.#..#######..#..##.#.###.#",
  "#.....#.###.###....#..#.#.#.....#",
  "#######.#.#.#.#.#.#.#.#.#.#######",
  "........##.#..#.#..######........",
  "#.#####...#####..###..#.#.#####..",
  "#.###..##.#####.#####..#..##.####",
  "#.##.##..#########..#...##..#.##.",
  ".##.#..##.#..#...###.###.#..####.",
  ".#..#.#.##....###...####...###.#.",
  "#..###.#..#..#.#.##...#..##...###",
  ".##..###..#..#####..#.#.####...#.",
  "..####...#...###.....##.###..##..",
  "#.##.####..###.#.#....####.####.#",
  ".#####..##..#...#.####.#####.##.#",
  "##.##.##..#..#.##.#..#...####.##.",
  "###..#..##.....#...#####.#.######",
  "#..#..##......#...##.##..#.###...",
  "###.....#.###..##...###..#...#..#",
  "#.#####.#.#.##.....#..#.##..##.#.",
  "#....#.....#....#.#####..##.####.",
  "#..#.##.##.##.#..#.#..#.#####....",
  "........#.##.#..####.#.##...#.###",
  "#######..###..##.#..##.##.#.#.##.",
  "#.....#.###.##..###.##.##...####.",
  "#.###.#.#.#.#..##....##.######.#.",
  "#.###.#.##.#.#.#..#....#.#..#.###",
  "#.###.#.#..######....#######.#...",
  "#.....#..#.#..##...###..##..###..",
  "#######.##..#..###....######...#.",
];

/** Fassung 1, Maske 5 — 21 × 21 Module. */
const EINZEICHEN_TEXT = "a";
const EINZEICHEN_ROWS = [
  "#######..#.##.#######",
  "#.....#.#.##..#.....#",
  "#.###.#.##.#..#.###.#",
  "#.###.#.#.##..#.###.#",
  "#.###.#..#..#.#.###.#",
  "#.....#...##..#.....#",
  "#######.#.#.#.#######",
  "........##...........",
  "#.....#.#.##.##..###.",
  "#..##......###.###..#",
  "..#.###..##.#.##.....",
  ".#.#.#.##..#####.#.#.",
  "##.#..####.##########",
  "........##..#.....#.#",
  "#######..###.#..####.",
  "#.....#...#...#...###",
  "#.###.#..###.#..###..",
  "#.###.#..#.#####.#...",
  "#.###.#..#.###.###.##",
  "#.....#...######.#...",
  "#######.#.#.#..#..##.",
];

/** Fassung 3, Maske 6 — 29 × 29 Module. */
const UMLAUTE_TEXT = "Grüße aus Nori — ÄÖÜ";
const UMLAUTE_ROWS = [
  "#######.###.####.####.#######",
  "#.....#.#..#.###......#.....#",
  "#.###.#.#....##..##...#.###.#",
  "#.###.#....##.##....#.#.###.#",
  "#.###.#.######.#.##...#.###.#",
  "#.....#......##...##..#.....#",
  "#######.#.#.#.#.#.#.#.#######",
  "..........###.#..#.##........",
  "#..######..#.####.##.#..#.###",
  "....#....###..#....##.####.#.",
  "#.#...##..###.#.....#.###.###",
  "##...#.####...##..#.#..#####.",
  "##.#####.#..###..#.#..##.####",
  "#.##.#..#..#......###.#.###..",
  "...##.##......##.##....#..#..",
  ".#..#..#..#.###.##..##..#....",
  "....####.##.#..#.##.#....###.",
  "###.##...####........#..####.",
  "###.#.#.#.#..##.##..###.#...#",
  "###.#...##.###.##.#.#.###.###",
  "####.##...##.#....#########.#",
  "........#...##..###.#...###.#",
  "#######.##..##.##..##.#.###..",
  "#.....#.#.#.##..#.###...#..#.",
  "#.###.#.##.###.###..######.#.",
  "#.###.#.#.#.###.#.####.#.###.",
  "#.###.#...#####.#.##.#.###.##",
  "#.....#...#...##.......####.#",
  "#######.#.###...###.#..##....",
];

/** Fassung 7, Maske 4 — 45 × 45 Module. */
const LANG_TEXT = "https://www.google.com/device?user_code=WDXR-KQPF&hl=dehttps://www.google.com/device?user_code=WDXR-KQPF&hl=de";
const LANG_ROWS = [
  "#######.##..#.##.#..##....#.###..#..#.#######",
  "#.....#..#.##.####.###.###.#.....#.#..#.....#",
  "#.###.#..#.####.#.#...##...#..#.##.#..#.###.#",
  "#.###.#.##.###..#...##...#..#..#...##.#.###.#",
  "#.###.#.#....#.#....#######.#####.###.#.###.#",
  "#.....#.##..#..#.#.##...#.##..##.#....#.....#",
  "#######.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#.#######",
  "........#..#.########...#..#..#.#.###........",
  "#...#.###...##.###..#####..#.#..###..#####..#",
  ".#####..#....##...####.##.#.###..#.######.#..",
  ".#....###.###.##...#..##..#..##.....#####.##.",
  ".##.#..###.##.###.....#...###.#.#...#...#....",
  "##...##..###...#..#.###.#####.####.#...#...#.",
  "#####..#.#..#..###.#####..#.#.##.#..#.#..#.#.",
  "..#...##.####....#.#.#....#...#...#...#.#.##.",
  ".###....#..#.##...##....#.#...#.#.#..###.....",
  "#..##.##...#...#..##...#..##.#..####.#...#..#",
  "#...##.##..##.#..#.###....##.##..#.##.######.",
  ".####.##.##..###.#.##.#...#.####.#..#.#.#....",
  "####.#.........#..##..##.###.##.###.#.##.#.##",
  ".########.##...#.#########...#..##..######...",
  "....#...##.#..#....##...#...####.#..#...###..",
  "...##.#.######..##.##.#.#...#..#..#.#.#.##.#.",
  "..###...#....#......#...####..#.#.###...#..#.",
  "..#######.#.#.##..#######....##.##########..#",
  "..#.#...###.....###..####.##..##.#...###.###.",
  "#..##.###...#..#..#.##.##.#.#####....#.....#.",
  "##.....#######.##....##..####.##..#.##......#",
  "..#####..#..##.##...##.#.##..##.###..#.###...",
  "####.#..#....##.##.#.###.###.#####.#.#.#.###.",
  "##.#..###..#...#...#.###.##.###.###....##.##.",
  "##.##..#.###.#..#.###...#..#....#...#.###..##",
  "#####.#.#.##..##..#..#.....#.#..#...#....#...",
  "####.#..###.#..#......##..#..###.#.....#.#.#.",
  "....#.##........##..###.#.#.######.#.#.......",
  ".####......###...#..#.##...###..###...#.#...#",
  "#..##.####.....##..######.##.####...########.",
  "........#.####.##.#.#...###..###.#.##...###..",
  "#######.#.########.##.#.##.##..#.##.#.#.##.#.",
  "#.....#..#.#..#.#..##...####..#.#.#.#...#..##",
  "#.###.#.#.#..############.##.#.###########...",
  "#.###.#........###.##..####..##.#.....###.##.",
  "#.###.#..#.###..#.##..#...#..###.#.#.##.####.",
  "#.....#...#.#.###.#.#.######...#..####.......",
  "#######.#..####...#.#.###.##..#.#...##.#.##.#",
];

test("QR-Code 3-M stimmt Modul für Modul mit der Referenz überein (device)", () => {
  const code = encodeQrCode(DEVICE_TEXT);
  assert.equal(code.version, 3);
  assert.equal(code.mask, 3);
  assert.equal(code.size, 29);
  assert.deepEqual(rows(DEVICE_TEXT), DEVICE_ROWS);
});

test("QR-Code 4-M stimmt Modul für Modul mit der Referenz überein (deviceMitCode)", () => {
  const code = encodeQrCode(DEVICEMITCODE_TEXT);
  assert.equal(code.version, 4);
  assert.equal(code.mask, 2);
  assert.equal(code.size, 33);
  assert.deepEqual(rows(DEVICEMITCODE_TEXT), DEVICEMITCODE_ROWS);
});

test("QR-Code 1-M stimmt Modul für Modul mit der Referenz überein (einZeichen)", () => {
  const code = encodeQrCode(EINZEICHEN_TEXT);
  assert.equal(code.version, 1);
  assert.equal(code.mask, 5);
  assert.equal(code.size, 21);
  assert.deepEqual(rows(EINZEICHEN_TEXT), EINZEICHEN_ROWS);
});

test("QR-Code 3-M stimmt Modul für Modul mit der Referenz überein (umlaute)", () => {
  const code = encodeQrCode(UMLAUTE_TEXT);
  assert.equal(code.version, 3);
  assert.equal(code.mask, 6);
  assert.equal(code.size, 29);
  assert.deepEqual(rows(UMLAUTE_TEXT), UMLAUTE_ROWS);
});

test("QR-Code 7-M stimmt Modul für Modul mit der Referenz überein (lang)", () => {
  const code = encodeQrCode(LANG_TEXT);
  assert.equal(code.version, 7);
  assert.equal(code.mask, 4);
  assert.equal(code.size, 45);
  assert.deepEqual(rows(LANG_TEXT), LANG_ROWS);
});

test("Die Fassung wächst mit der Länge und nicht früher", () => {
  // Fassung 1-M trägt 16 Datencodewörter: vier Bit Modus, acht Bit Anzahl,
  // der Rest Nutzlast — also 14 Byte.
  assert.equal(encodeQrCode("x".repeat(14)).version, 1);
  assert.equal(encodeQrCode("x".repeat(15)).version, 2);
  // Ab Fassung 10 wäre das Anzahlfeld 16 Bit breit; so weit kommt Nori nicht,
  // und der Encoder sagt das statt einen unlesbaren Code zu liefern.
  assert.equal(encodeQrCode("x".repeat(213)).version, 10);
  assert.throws(() => encodeQrCode("x".repeat(214)), QrError);
});

test("Der SVG-Pfad enthält genau die dunklen Module", () => {
  const code = encodeQrCode("nori");
  const dark = code.modules.reduce((sum, row) => sum + row.filter(Boolean).length, 0);
  const path = qrSvgPath(code);
  assert.equal(path.split("M").length - 1, dark);
  // Ein einziger Pfad, keine tausend Rechtecke: auf dem Fernseher ist jeder
  // zusätzliche DOM-Knoten teuer.
  assert.ok(!path.includes("<"));
});

test("Derselbe Text ergibt denselben Code", () => {
  // Kein Zufall in der Maskenwahl: ein Code, der sich bei jedem Bild ändert,
  // wäre für eine Kamera nicht zu fassen.
  assert.deepEqual(rows("https://www.google.com/device"), rows("https://www.google.com/device"));
});

// MARK: - Welche Adresse in den Code kommt

test("Die vollständige Adresse von Google hat Vorrang", () => {
  // RFC 8628 sieht `verification_uri_complete` genau dafür vor: der Code steckt
  // dann schon darin, und der Nutzer muss am Telefon nichts abtippen.
  assert.equal(deviceQrPayload({
    deviceCode: "dc",
    userCode: "WDXR-KQPF",
    verificationUrl: "https://www.google.com/device",
    verificationUrlComplete: "https://www.google.com/device?user_code=WDXR-KQPF",
    expiresAt: 0,
    intervalMs: 5000,
  }), "https://www.google.com/device?user_code=WDXR-KQPF");
});

test("Ohne vollständige Adresse kommt die schlichte in den Code", () => {
  // Und **nur** die. Eine Adresse mit angehängtem `user_code` selbst zu bauen
  // wäre geraten: welchen Parameter Google dort erwartet, steht nirgends zu,
  // und ein falscher führt auf eine Fehlerseite.
  const payload = deviceQrPayload({
    deviceCode: "dc",
    userCode: "WDXR-KQPF",
    verificationUrl: "https://www.google.com/device",
    expiresAt: 0,
    intervalMs: 5000,
  });
  assert.equal(payload, "https://www.google.com/device");
  assert.ok(!payload.includes("WDXR"));
  assert.ok(!payload.includes("?"));
});
