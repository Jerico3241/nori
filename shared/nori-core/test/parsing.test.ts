import assert from "node:assert/strict";
import { test } from "node:test";
import "./setup.js";

import * as aniworld from "../src/parse/aniworld.js";
import * as serienstream from "../src/parse/serienstream.js";
import { berlinTime, toAniworldPath } from "../src/parse/common.js";
import * as fx from "./fixtures.js";

test("AniWorld-Katalog führt denselben Slug in mehreren Genres zusammen", () => {
  const items = aniworld.parseCatalog(fx.aniworldCatalog);
  assert.equal(items.length, 2);
  const onePiece = items.find((i) => i.slug === "one-piece");
  assert.ok(onePiece);
  assert.deepEqual(onePiece.genres, ["Action", "Abenteuer"]);
  // Alternativtitel gleich dem Haupttitel fällt raus.
  assert.deepEqual(onePiece.alts, ["Wan Pisu"]);
  assert.equal(items.find((i) => i.slug === "naruto")?.alts.length, 0);
});

test("AniWorld-Serie liest Titel, Beschreibung, Cover, Genres, Staffeln und Folgen", () => {
  const detail = aniworld.parseSeries(fx.aniworldSeries, "one-piece", null);
  assert.equal(detail.title, "One Piece");
  assert.equal(detail.description, "Ruffy will Piratenkönig werden.");
  assert.deepEqual(detail.alts, ["Wan Pisu"]);
  assert.ok(detail.coverPath?.includes("/public/img/cover/one-piece"));
  assert.equal(detail.yearStart, "1999");
  assert.equal(detail.yearEnd, "2026");
  assert.equal(detail.fsk, "12");
  assert.equal(detail.imdb, "tt0388629");
  // „GerSub" ist eine Sprachangabe, kein Genre.
  assert.deepEqual(detail.genres, ["Action", "Abenteuer"]);
  assert.deepEqual(detail.seasons.map((s) => s.id), ["1", "2", "filme"]);
  assert.equal(detail.activeSeason, "1");
  assert.equal(detail.episodes.length, 2);
  assert.equal(detail.episodes[0].germanTitle, "Ich bin Ruffy");
  assert.equal(detail.episodes[0].englishTitle, "I'm Luffy");
  assert.equal(detail.episodes[0].path, "/anime/stream/one-piece/staffel-1/episode-1");
  assert.deepEqual(detail.episodes[0].hosters, ["VOE", "Vidmoly"]);
  assert.deepEqual(detail.episodes[0].languages, ["DE", "GerSub"]);
  assert.deepEqual(detail.episodes[1].languages, ["EN"]);
});

test("AniWorld-Folgenseite entfernt Dubletten und behält Sprache je Hoster", () => {
  const info = aniworld.parseWatch(fx.aniworldWatch, "/anime/stream/one-piece/staffel-1/episode-1");
  assert.equal(info.germanTitle, "Ich bin Ruffy");
  assert.equal(info.englishTitle, "I'm Luffy");
  assert.equal(info.hosters.length, 3);
  assert.deepEqual(info.hosters.map((h) => h.name), ["VOE", "Vidmoly", "Filemoon"]);
  assert.deepEqual(info.hosters.map((h) => h.lang), ["DE", "GerSub", "EN"]);
  assert.equal(info.hosters[0].redirectPath, "/redirect/123456");
  assert.equal(info.hosters[2].redirectPath, "/redirect/345678");
});

test("AniWorld-Kalender verschmilzt gleiche Folgen und liest Zeit in Berliner Zeit", () => {
  const entries = aniworld.parseCalendar(fx.aniworldCalendar);
  assert.equal(entries.length, 3);
  const onePiece = entries.find((e) => e.slug === "one-piece");
  assert.ok(onePiece);
  assert.deepEqual(onePiece.languages, ["DE", "JP"]);
  assert.equal(onePiece.season, "21");
  assert.equal(onePiece.episode, 1120);
  assert.equal(onePiece.dayKey, "2026-09-14");
  assert.equal(onePiece.dayLabel, "Montag, 14. September");
  assert.equal(onePiece.airingAt, berlinTime(2026, 9, 14, 9, 30));
  assert.ok(onePiece.coverPath?.includes("/public/img/cover/"));
  const frieren = entries.find((e) => e.slug === "frieren");
  assert.deepEqual(frieren?.languages, ["GerSub"]);
  // Ohne Cover im Markup bleibt das Feld leer statt geraten zu werden.
  assert.equal(frieren?.coverPath, null);
});

test("AniWorld-Kalender hält fest, ob eine Uhrzeit genannt wurde", () => {
  const entries = aniworld.parseCalendar(fx.aniworldCalendar);
  assert.equal(entries.find((e) => e.slug === "frieren")?.hasTime, true);
  // Ohne Uhrzeit im Markup steht `airingAt` auf Mitternacht. Sortieren lässt
  // sich damit, anzeigen nicht — genau dafür gibt es das Feld.
  const ohneZeit = entries.find((e) => e.slug === "ohne-zeit");
  assert.equal(ohneZeit?.hasTime, false);
  assert.equal(ohneZeit?.airingAt, berlinTime(2026, 9, 15, 0, 0));
});

test("Serienstream-Katalog lässt das Genre Anime aus", () => {
  const items = serienstream.parseCatalog(fx.serienstreamCatalog);
  const slugs = items.map((i) => i.slug).sort();
  assert.deepEqual(slugs, ["breaking-bad", "dexter"]);
  const dexter = items.find((i) => i.slug === "dexter");
  assert.deepEqual(dexter?.genres, ["Drama"]);
  assert.deepEqual(dexter?.alts, ["Dexter Morgan"]);
});

test("Serienstream-Serie bevorzugt die sichtbare Beschreibung", () => {
  const detail = serienstream.parseSeries(fx.serienstreamSeries, "dexter", null);
  assert.equal(detail.title, "Dexter");
  assert.equal(detail.description, "Ein Forensiker mit einem Nebengewerbe.");
  assert.equal(detail.coverPath, "https://s.to/media/images/channel/desktop/dexter-7sqv7dhs?format=avif");
  assert.deepEqual(detail.seasons.map((s) => s.id), ["1", "2", "filme"]);
  assert.equal(detail.activeSeason, "2");
  assert.equal(detail.episodes.length, 2);
  assert.equal(detail.episodes[0].path, "/serie/dexter/staffel-2/episode-1");
  assert.deepEqual(detail.episodes[0].hosters, ["VOE"]);
  assert.deepEqual(detail.episodes[0].languages, ["DE"]);
  assert.deepEqual(detail.episodes[1].hosters, ["Vidoza"]);
});

test("Serienstream-Folgenseite übernimmt keine fremden Adressen", () => {
  const info = serienstream.parseWatch(fx.serienstreamWatch, "/serie/dexter/staffel-2/episode-1");
  assert.equal(info.hosters.length, 2);
  assert.deepEqual(info.hosters.map((h) => h.redirectPath), ["/r?t=abc123", "/r?t=def456"]);
  assert.deepEqual(info.hosters.map((h) => h.lang), ["DE", "GerSub"]);
});

test("Serienstream-Kalender überliest Datensätze ohne gültiges Datum", () => {
  const entries = serienstream.parseCalendar(fx.serienstreamCalendarJSON);
  assert.equal(entries.length, 3);
  assert.ok(!entries.some((e) => e.slug === "ignoriert"));
  const dexter = entries.filter((e) => e.slug === "dexter");
  assert.equal(dexter.length, 2);
  assert.deepEqual(dexter.map((e) => e.languages).flat().sort(), ["DE", "EN"]);
  assert.equal(dexter[0].dayLabel, "Montag, 14. September");
  assert.equal(dexter[0].airingAt, berlinTime(2026, 9, 14, 20, 15));
});

test("Serienstream-Kalender hält fest, ob eine Uhrzeit genannt wurde", () => {
  const entries = serienstream.parseCalendar(fx.serienstreamCalendarJSON);
  assert.equal(entries.find((e) => e.slug === "dexter")?.hasTime, true);
  // Fehlt `time` im Datensatz, gibt es keine Uhrzeit — nicht Mitternacht.
  assert.equal(entries.find((e) => e.slug === "ohne-zeit")?.hasTime, false);
});

test("toAniworldPath räumt Adressen auf", () => {
  assert.equal(toAniworldPath("https://aniworld.to/anime/stream/one-piece/staffel-1/"), "/anime/stream/one-piece/staffel-1");
  assert.equal(toAniworldPath("/serie/dexter/staffel-2/episode-1?ref=x"), "/serie/dexter/staffel-2/episode-1");
  assert.equal(toAniworldPath("/redirect/123456"), "/redirect/123456");
  assert.equal(toAniworldPath("/r?t=abc#frag"), "/r?t=abc");
  assert.equal(toAniworldPath("kein-pfad"), "");
});
