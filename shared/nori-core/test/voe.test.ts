import assert from "node:assert/strict";
import { test } from "node:test";

import { decodeVoe, extractVoe, padBase64, rot13 } from "../src/hoster/voe.js";
import { firstMedia, siteMedia, toEmbed } from "../src/hoster/sites.js";
import { extractBounce, htmlRedirectTarget } from "../src/hoster/resolver.js";

/** Die Verschlüsselung von VOE rückwärts, damit der Test echte Eingaben erzeugt. */
function encodeVoe(payload: unknown): string {
  const json = JSON.stringify(payload);
  const b64 = btoa(unescape(encodeURIComponent(json)));
  const reversed = b64.split("").reverse().join("");
  let shifted = "";
  for (const ch of reversed) shifted += String.fromCharCode((ch.charCodeAt(0) + 3) & 0xff);
  let bin = "";
  for (const ch of shifted) bin += ch;
  const outer = btoa(bin);
  // Die Tokens streut VOE zufällig ein; ein einzelner reicht für den Test.
  const withToken = outer.replace(/^(.{4})/, "$1@$");
  return rot13(withToken);
}

test("rot13 ist seine eigene Umkehrung", () => {
  assert.equal(rot13(rot13("Hallo Welt 123")), "Hallo Welt 123");
});

test("padBase64 füllt auf ein Vielfaches von vier auf", () => {
  assert.equal(padBase64("ab"), "ab==");
  assert.equal(padBase64("abcd"), "abcd");
});

test("decodeVoe dreht die Verschleierung zurück", () => {
  const cfg = { source: "https://cdn.example/master.m3u8", direct_access_url: "https://cdn.example/v.mp4" };
  const decoded = decodeVoe(encodeVoe(cfg));
  assert.deepEqual(decoded, cfg);
});

test("decodeVoe gibt bei Müll null zurück statt zu werfen", () => {
  assert.equal(decodeVoe("###"), null);
  assert.equal(decodeVoe(""), null);
});

test("extractVoe liest das JSON-Script-Tag und bevorzugt HLS", () => {
  const blob = encodeVoe({ source: "https://cdn.example/master.m3u8", direct_access_url: "https://cdn.example/v.mp4" });
  const html = `<html><script type="application/json">${JSON.stringify([blob])}</script></html>`;
  assert.deepEqual(extractVoe(html), {
    source: "https://cdn.example/master.m3u8",
    direct: "https://cdn.example/v.mp4",
  });
  assert.deepEqual(siteMedia(html, "VOE"), { kind: "hls", url: "https://cdn.example/master.m3u8" });
});

test("VOE fällt auf die direkte Datei zurück, wenn kein HLS dabei ist", () => {
  const blob = encodeVoe({ direct_access_url: "https://cdn.example/v.mp4" });
  const html = `<script type="application/json">${JSON.stringify([blob])}</script>`;
  assert.deepEqual(siteMedia(html, "VOE"), { kind: "mp4", url: "https://cdn.example/v.mp4" });
});

test("Embed-Umschreibung nur für die Hoster, die sie brauchen", () => {
  assert.equal(toEmbed("https://filemoon.sx/d/abc", "Filemoon"), "https://filemoon.sx/e/abc");
  assert.equal(toEmbed("https://vidmoly.to/v/abc", "Vidmoly"), "https://vidmoly.to/e/abc");
  assert.equal(toEmbed("https://dood.li/d/abc", "Doodstream"), "https://dood.li/e/abc");
  assert.equal(toEmbed("https://voe.sx/e/abc", "VOE"), "https://voe.sx/e/abc");
  assert.equal(toEmbed("https://neu.example/d/abc", "Unbekannt"), "https://neu.example/d/abc");
});

test("Allgemeine Streamsuche findet HLS vor MP4 und blockt Unsicheres", () => {
  assert.deepEqual(firstMedia(`file: "https://cdn.example/x.m3u8"`),
    { kind: "hls", url: "https://cdn.example/x.m3u8" });
  assert.deepEqual(firstMedia(`src="https://cdn.example/x.mp4"`),
    { kind: "mp4", url: "https://cdn.example/x.mp4" });
  assert.equal(firstMedia(`file: "https://127.0.0.1/x.m3u8"`), null);
  assert.equal(firstMedia(`file: "http://cdn.example/x.m3u8"`), null);
  assert.equal(firstMedia("<html>nichts</html>"), null);
});

test("Weiterleitungen aus HTML lesen", () => {
  assert.equal(
    htmlRedirectTarget(`<meta http-equiv="refresh" content="0;url=https://voe.sx/e/abc">`),
    "https://voe.sx/e/abc",
  );
  assert.equal(
    htmlRedirectTarget(`<script>window.location.href = "https://voe.sx/e/abc";</script>`),
    "https://voe.sx/e/abc",
  );
  assert.equal(
    htmlRedirectTarget(`<iframe src="https://voe.sx/e/abc"></iframe>`),
    "https://voe.sx/e/abc",
  );
  assert.equal(htmlRedirectTarget("<html></html>"), null);
  assert.equal(
    extractBounce(`window.location.href='https://voe.sx/e/xyz'`),
    "https://voe.sx/e/xyz",
  );
  assert.equal(extractBounce(`window.location.href='https://translate.google.com/x'`), null);
});
