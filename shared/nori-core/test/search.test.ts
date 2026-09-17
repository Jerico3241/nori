// Die Stufen der Titelsuche und die Tippfehlertoleranz.
//
// Dieselben Fälle prüft `native/Tests/NoriCoreTests/CatalogSearchRankingTests.swift`
// für den Swift-Kern. Weichen die beiden ab, sucht der Fernseher anders als das
// iPhone — auf demselben Katalog, mit derselben Eingabe.

import assert from "node:assert/strict";
import test from "node:test";

import { fuzzyScore, normalizeTitle, rankSearch, searchScore, type Searchable } from "../src/index.js";

function entry(title: string, alts: string[] = []): Searchable {
  return { title, alts };
}

function score(title: string, alts: string[], query: string): number {
  return searchScore(entry(title, alts), normalizeTitle(query));
}

// MARK: - Stufen

test("Ein gleicher Titel ist die beste Stufe", () => {
  assert.equal(score("Frieren", [], "frieren"), 0);
  assert.equal(score("Re:ZERO", [], "re zero"), 0);
  assert.equal(score("Pokémon", [], "pokemon"), 0);
});

test("Anfang schlägt Vorkommen schlägt Alternativtitel", () => {
  assert.equal(score("Attack on Titan", [], "attack"), 1);
  assert.equal(score("Attack on Titan", [], "titan"), 2);
  assert.equal(score("Dämonenjäger", ["Demon Slayer"], "demon slayer"), 3);
});

test("Die Umschrift findet den deutschen Titel", () => {
  const item = entry("Attack on Titan", ["Shingeki no Kyojin", "Angriff auf Titan"]);
  assert.ok(searchScore(item, normalizeTitle("shingeki no kyojin")) >= 0);
  assert.ok(searchScore(item, normalizeTitle("angriff auf titan")) >= 0);
});

test("Jedes Wort muss vorkommen", () => {
  assert.equal(score("Attack on Titan", ["Shingeki no Kyojin"], "kyojin attack"), 4);
  assert.equal(score("Attack on Titan", [], "titan drama"), -1);
});

test("Kein Treffer ist minus eins", () => {
  assert.equal(score("Frieren", [], "monster"), -1);
});

// MARK: - Tippfehler

test("Ein Buchstabe daneben trifft trotzdem", () => {
  const item = entry("Dämonenjäger");
  assert.equal(searchScore(item, normalizeTitle("damonenjager")), 0);
  assert.equal(searchScore(item, normalizeTitle("damonejager")), -1);
  assert.equal(fuzzyScore(item, normalizeTitle("damonejager")), 5);
});

test("Kurze Wörter vertragen keinen Tippfehler", () => {
  assert.equal(fuzzyScore(entry("Dark"), normalizeTitle("dak")), -1);
  assert.equal(fuzzyScore(entry("Dark"), normalizeTitle("bark")), 5);
  assert.equal(fuzzyScore(entry("Dark"), normalizeTitle("da")), -1);
});

test("Ziffern werden nie korrigiert", () => {
  const item = entry("Titel 1999");
  assert.equal(fuzzyScore(item, normalizeTitle("titel 1998")), -1);
  assert.equal(fuzzyScore(item, normalizeTitle("titel 1999")), 5);
});

// MARK: - Reihenfolge

test("Die beste Stufe steht vorn", () => {
  const titles = ["Titan Games", "Attack on Titan", "Titan"];
  assert.deepEqual(
    rankSearch(titles, "titan", (title) => entry(title)),
    ["Titan", "Titan Games", "Attack on Titan"],
  );
});

test("Eine zu kurze Eingabe trifft alles", () => {
  const titles = ["Frieren", "Dark"];
  assert.deepEqual(rankSearch(titles, "d", (title) => entry(title)), titles);
  assert.deepEqual(rankSearch(titles, "", (title) => entry(title)), titles);
});

test("Tippfehler zählen erst, wenn die strengen Stufen wenig finden", () => {
  const many = Array.from({ length: 30 }, (_, index) => `Frieren Teil ${index}`);
  many.push("Frieran");
  const ranked = rankSearch(many, "frieren", (title) => entry(title));
  assert.equal(ranked.length, 30);
  assert.ok(!ranked.includes("Frieran"));

  assert.deepEqual(
    rankSearch(["Frieren", "Frieran", "Dark"], "frieren", (title) => entry(title)),
    ["Frieren", "Frieran"],
  );
});

test("Bei gleicher Stufe entscheidet der Aufrufer", () => {
  const titles = ["Titan B", "Titan A"];
  assert.deepEqual(
    rankSearch(titles, "titan", (title) => entry(title), (a, b) => a.localeCompare(b)),
    ["Titan A", "Titan B"],
  );
  // Ohne Vorgabe bleibt die Eingabereihenfolge.
  assert.deepEqual(rankSearch(titles, "titan", (title) => entry(title)), titles);
});
