// Die Teile des Nori-Servers, die ohne Netz prüfbar sind.
//
// Die Auswahl ist keine Bequemlichkeit: Es sind genau die Stellen, an denen ein
// Fehler den Dienst von einem Helfer in ein Loch verwandelt.
//
// - **`rewriteM3U8`** entscheidet, welche Adressen der Fernseher lädt. Fehlt
//   die Umschreibung, holt er die Segmente direkt beim Hoster — ohne `Referer`
//   und damit mit 403. Schreibt sie zu viel um, führt jede Zeile einer
//   Playlist durch den Server, auch die, die nichts damit zu tun hat.
// - **`routeFor`** entscheidet, welche TMDB-Pfade überhaupt hinausgehen. Ohne
//   diese Liste wäre `/api/tmdb/…` ein offener Zugang zu allem, was mit dem
//   Schlüssel des Servers erreichbar ist — einschließlich der schreibenden
//   Endpunkte.
// - **`cleanParams`** entfernt `api_key` aus der Anfrage. Ohne das könnte ein
//   Client einen fremden Schlüssel unterschieben und den Server als
//   Verschleierung benutzen.

import assert from "node:assert/strict";
import { test } from "node:test";

import { BUILT_IN_TMDB_KEY } from "@nori/core";
import { cleanParams, hasTMDBKey, routeFor, tmdbKeyOrigin } from "../src/tmdb.js";
import { rewriteM3U8 } from "../src/playlist.js";

// MARK: - HLS-Playlisten

test("rewriteM3U8 biegt Segmentadressen auf den eigenen Weiterreicher um", () => {
  const playlist = [
    "#EXTM3U",
    "#EXT-X-VERSION:3",
    "#EXTINF:10.0,",
    "segment0.ts",
    "#EXTINF:10.0,",
    "https://cdn.example.com/segment1.ts",
    "#EXT-X-ENDLIST",
  ].join("\n");

  const out = rewriteM3U8(playlist, "https://cdn.example.com/hls/index.m3u8", "https://hoster.example/");
  const lines = out.split("\n");

  assert.equal(lines[0], "#EXTM3U");
  assert.equal(lines[1], "#EXT-X-VERSION:3");
  // Relativ **und** absolut werden umgebogen, beide mit Referer.
  assert.ok(lines[3].startsWith("/api/stream?u="));
  assert.ok(lines[3].includes(encodeURIComponent("https://cdn.example.com/hls/segment0.ts")));
  assert.ok(lines[3].includes(`r=${encodeURIComponent("https://hoster.example/")}`));
  assert.ok(lines[5].includes(encodeURIComponent("https://cdn.example.com/segment1.ts")));
  assert.equal(lines[6], "#EXT-X-ENDLIST");
});

test("rewriteM3U8 fasst auch die URI in Schlüssel- und Map-Zeilen", () => {
  const playlist = [
    '#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x00',
    '#EXT-X-MAP:URI="init.mp4"',
    '#EXT-X-MEDIA:TYPE=AUDIO,URI="audio/index.m3u8",NAME="Deutsch"',
  ].join("\n");

  const out = rewriteM3U8(playlist, "https://cdn.example.com/hls/index.m3u8", null);
  // Ohne diese Zeilen bleibt der Schlüssel beim Hoster — und ohne Schlüssel
  // ist ein verschlüsselter Stream nicht abspielbar.
  assert.ok(out.includes('URI="/api/stream?u='));
  assert.equal(out.split('URI="/api/stream').length - 1, 3);
  // Die übrigen Angaben der Zeile bleiben unangetastet.
  assert.ok(out.includes("METHOD=AES-128"));
  assert.ok(out.includes("IV=0x00"));
  assert.ok(out.includes('NAME="Deutsch"'));
});

test("rewriteM3U8 lässt unsichere Ziele in Ruhe", () => {
  // Eine Playlist, die auf das Heimnetz des Servers zeigt, wird nicht
  // weitergereicht. `isSafeRemoteURL` aus dem Kern entscheidet das; hier wird
  // geprüft, dass die Playlist-Umschreibung sie tatsächlich fragt.
  const playlist = ["http://192.168.1.1/admin.ts", "http://localhost:8730/api/health"].join("\n");
  const out = rewriteM3U8(playlist, "https://cdn.example.com/hls/index.m3u8", null);
  assert.equal(out, playlist);
});

test("rewriteM3U8 lässt leere Zeilen und Kommentare ohne URI stehen", () => {
  const playlist = ["#EXTM3U", "", "#EXT-X-TARGETDURATION:10", ""].join("\n");
  assert.equal(rewriteM3U8(playlist, "https://cdn.example.com/x.m3u8", null), playlist);
});

// MARK: - TMDB-Pfade

test("nur die freigegebenen TMDB-Pfade gehen hinaus", () => {
  for (const path of [
    "search/tv",
    "trending/tv/week",
    "trending/tv/day",
    "tv/popular",
    "discover/tv",
    "tv/1429",
    "tv/1429/images",
    "tv/1429/alternative_titles",
    "tv/1429/recommendations",
    "tv/1429/similar",
    "tv/1429/season/4",
  ]) {
    assert.notEqual(routeFor(path), null, `${path} muss erlaubt sein`);
  }
});

test("alles andere wird abgelehnt", () => {
  for (const path of [
    // Schreibende Endpunkte: mit dem Schlüssel des Servers wäre das fremde
    // Kontoführung.
    "account/lists",
    "list",
    "tv/1429/rating",
    "authentication/token/new",
    // Wege, einen Pfad vorzutäuschen.
    "../account",
    "tv/1429/season/4/episode/1/rating",
    "search/person",
    "movie/550",
    "",
  ]) {
    assert.equal(routeFor(path), null, `${path} darf nicht erlaubt sein`);
  }
});

test("die Gültigkeitsdauer passt zur Art der Antwort", () => {
  const day = 86_400_000;
  // Eine Serienkennung ändert sich nie, der Wochentrend täglich.
  assert.ok(routeFor("search/tv")!.maxAge >= 7 * day);
  assert.ok(routeFor("tv/1429/season/1")!.maxAge >= 7 * day);
  assert.ok(routeFor("trending/tv/week")!.maxAge <= day);
});

// MARK: - Anfrageparameter

test("cleanParams entfernt den Schlüssel aus der Anfrage", () => {
  const source = new URLSearchParams({
    api_key: "fremder-schluessel",
    language: "de-DE",
    query: "Frieren",
  });
  const clean = cleanParams(source);
  assert.equal(clean.get("api_key"), null);
  assert.equal(clean.get("language"), "de-DE");
  assert.equal(clean.get("query"), "Frieren");
});

test("cleanParams lässt nur bekannte Parameter durch", () => {
  const source = new URLSearchParams({
    session_id: "geheim",
    append_to_response: "credits",
    sort_by: "popularity.desc",
    "air_date.gte": "2026-01-01",
  });
  const clean = cleanParams(source);
  assert.equal(clean.get("session_id"), null);
  assert.equal(clean.get("append_to_response"), null);
  assert.equal(clean.get("sort_by"), "popularity.desc");
  assert.equal(clean.get("air_date.gte"), "2026-01-01");
});

test("cleanParams verwirft übermäßig lange Werte", () => {
  const source = new URLSearchParams({ query: "x".repeat(500) });
  assert.equal(cleanParams(source).get("query"), null);
});

test("cleanParams ordnet die Parameter, damit der Schlüssel stabil ist", () => {
  // Der Zwischenspeicher wird über `pfad?parameter` geschlüsselt. Ohne feste
  // Reihenfolge wären `?a=1&b=2` und `?b=2&a=1` zwei Einträge für dieselbe
  // Antwort — und der Speicher füllte sich mit Dubletten.
  const first = cleanParams(new URLSearchParams({ page: "1", language: "de-DE" })).toString();
  const second = cleanParams(new URLSearchParams({ language: "de-DE", page: "1" })).toString();
  assert.equal(first, second);
});



// MARK: - Der Schlüssel

test("ohne NORI_TMDB_KEY greift der mitgelieferte", () => {
  // Ein frisch aufgesetzter Server kann damit sofort TMDB. Der Lauf setzt die
  // Umgebungsvariable nicht, also ist das hier der geprüfte Zustand.
  assert.equal(hasTMDBKey(), true);
  assert.equal(tmdbKeyOrigin(), process.env.NORI_TMDB_KEY ? "own" : "builtIn");
});

test("der mitgelieferte Schlüssel kommt aus dem Kern", () => {
  // Nicht im Server hinterlegt: eine zweite Kopie wäre eine, die beim
  // Tauschen übersehen wird.
  assert.match(BUILT_IN_TMDB_KEY, /^[0-9a-f]{32}$/);
});
