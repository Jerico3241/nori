// Der Geräteabgleich, gegen die gemeinsamen Fälle aus
// `config/sync-fixtures.json`.
//
// Dieselbe Datei liest `native/Tests/NoriCoreTests/LibrarySyncTests.swift`.
// Das ist der eigentliche Punkt: nicht nur, dass TypeScript richtig rechnet,
// sondern dass TypeScript und Swift **gleich** rechnen. Läuft das auseinander,
// entscheidet der Fernseher anders als das iPhone, beide schreiben ihr
// Ergebnis zurück, und die Bibliothek pendelt zwischen zwei Ständen — ein
// Fehler, den niemand als Konflikt erkennt, weil jedes Gerät für sich
// betrachtet richtig aussieht.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { mergeLibrarySnapshots, normalizedSnapshot } from "../src/sync.js";
import type { LibraryBag } from "../src/library.js";

interface Expectation {
  favorites?: string[];
  favoriteSource?: Record<string, string>;
  recents?: string[];
  progress?: Record<string, number>;
  preferences?: Record<string, string>;
  titles?: Record<string, string>;
}

interface FixtureCase {
  name: string;
  snapshots: LibraryBag[];
  expect: Expectation;
}

/**
 * Die Fixture-Datei liegt in der Wurzel des Repositorys, dieser Test je nach
 * Lauf in `test/` oder in `dist/test/`. Statt die Tiefe zu raten wird nach
 * oben gesucht — das überlebt auch eine geänderte Ausgabestruktur.
 */
function loadFixtures(): { now: number; cases: FixtureCase[] } {
  let dir = dirname(fileURLToPath(import.meta.url));
  for (let depth = 0; depth < 8; depth += 1) {
    try {
      return JSON.parse(readFileSync(join(dir, "config/sync-fixtures.json"), "utf8"));
    } catch {
      dir = dirname(dir);
    }
  }
  throw new Error("config/sync-fixtures.json nicht gefunden");
}

const fixtures = loadFixtures();

/** „2" statt „2.0" — dieselbe Zeichenkette, die der Swift-Test bildet. */
function preferenceText(bag: LibraryBag): Record<string, string> {
  const out: Record<string, string> = {};
  if (bag.langPref !== undefined) out.langPref = bag.langPref;
  if (bag.hosterPref !== undefined) out.hosterPref = bag.hosterPref;
  if (bag.resumeEnabled !== undefined) out.resumeEnabled = bag.resumeEnabled ? "true" : "false";
  if (bag.preferredQuality !== undefined) out.preferredQuality = bag.preferredQuality;
  if (bag.autoplayNext !== undefined) out.autoplayNext = bag.autoplayNext ? "true" : "false";
  if (bag.playbackSpeed !== undefined) out.playbackSpeed = String(bag.playbackSpeed);
  if (bag.provider !== undefined) out.provider = bag.provider;
  if (bag.scope !== undefined) out.scope = bag.scope;
  return out;
}

/**
 * Ein Ergebnis auf eine vergleichbare Zeichenkette bringen. Alles sortiert:
 * ein Vergleich, der an der Schlüsselreihenfolge hängt, prüft die Reihenfolge
 * statt den Inhalt.
 */
function summary(bag: LibraryBag): string {
  const pairs = (record: Record<string, unknown> | undefined, render: (value: never) => string) =>
    Object.entries(record ?? {}).sort(([a], [b]) => (a < b ? -1 : 1))
      .map(([key, value]) => `${key}:${render(value as never)}`).join(",");

  return [
    `favorites=${bag.favorites.join(",")}`,
    `source=${pairs(bag.favoriteSource, (v: string) => v)}`,
    `added=${pairs(bag.favoriteAddedAt, (v: number) => String(Math.trunc(v)))}`,
    `recents=${bag.recents.map((item) => `${item.slug}@${Math.trunc(item.viewedAt)}`).join(",")}`,
    `progress=${Object.entries(bag.progress).sort(([a], [b]) => (a < b ? -1 : 1))
      .map(([key, item]) => `${key}:${Math.trunc(item.positionSec)}:${Math.trunc(item.updatedAt)}`).join(",")}`,
    `titles=${pairs(bag.titles, (v: string) => v)}`,
    `prefs=${pairs(preferenceText(bag), (v: string) => v)}`,
    `historyClearedAt=${Math.trunc(bag.sync?.historyClearedAt ?? 0)}`,
    `progressClearedAt=${Math.trunc(bag.sync?.progressClearedAt ?? 0)}`,
    `marks=${Object.entries(bag.sync?.favorites ?? {}).sort(([a], [b]) => (a < b ? -1 : 1))
      .map(([key, mark]) => `${key}:${mark.isFavorite}:${Math.trunc(mark.updatedAt)}`).join(",")}`,
    `removed=${pairs(bag.sync?.recentsRemoved, (v: number) => String(Math.trunc(v)))}`,
  ].join("\n");
}

function permutations<T>(items: T[]): T[][] {
  if (items.length <= 1) return [items];
  if (items.length > 5) return [[...items].reverse()];
  const out: T[][] = [];
  items.forEach((item, index) => {
    const rest = items.filter((_, other) => other !== index);
    for (const tail of permutations(rest)) out.push([item, ...tail]);
  });
  return out;
}

test("Die gemeinsamen Fälle ergeben dasselbe wie im Swift-Kern", () => {
  assert.ok(fixtures.cases.length > 0, "Die Fixture-Datei ist leer — dann prüft dieser Test nichts.");

  for (const fixture of fixtures.cases) {
    const merged = mergeLibrarySnapshots(fixture.snapshots, fixtures.now);
    const expect = fixture.expect;

    if (expect.favorites) {
      assert.deepEqual(merged.favorites, expect.favorites, `${fixture.name}: Merkliste`);
    }
    for (const [slug, source] of Object.entries(expect.favoriteSource ?? {})) {
      assert.equal(merged.favoriteSource?.[slug], source, `${fixture.name}: Quelle von ${slug}`);
    }
    if (expect.recents) {
      assert.deepEqual(merged.recents.map((item) => item.slug), expect.recents, `${fixture.name}: Verlauf`);
    }
    if (expect.progress) {
      assert.deepEqual(
        Object.keys(merged.progress).sort(),
        Object.keys(expect.progress).sort(),
        `${fixture.name}: Fortschritts-Schlüssel`,
      );
      for (const [key, position] of Object.entries(expect.progress)) {
        assert.equal(merged.progress[key]?.positionSec, position, `${fixture.name}: Position ${key}`);
      }
    }
    if (expect.preferences) {
      const actual = preferenceText(merged);
      for (const [key, value] of Object.entries(expect.preferences)) {
        assert.equal(actual[key], value, `${fixture.name}: Einstellung ${key}`);
      }
    }
    for (const [slug, title] of Object.entries(expect.titles ?? {})) {
      assert.equal(merged.titles[slug], title, `${fixture.name}: Titel ${slug}`);
    }
  }
});

test("Die Reihenfolge der Dateien ändert das Ergebnis nicht", () => {
  // Drive gibt Dateien in keiner zugesicherten Reihenfolge heraus, und zwei
  // Geräte sehen sie deshalb verschieden.
  for (const fixture of fixtures.cases) {
    const reference = summary(mergeLibrarySnapshots(fixture.snapshots, fixtures.now));
    for (const order of permutations(fixture.snapshots)) {
      assert.equal(
        summary(mergeLibrarySnapshots(order, fixtures.now)),
        reference,
        `${fixture.name}: Ergebnis hängt an der Reihenfolge`,
      );
    }
  }
});

test("Zweimal zusammenführen ändert nichts mehr", () => {
  for (const fixture of fixtures.cases) {
    const once = mergeLibrarySnapshots(fixture.snapshots, fixtures.now);
    const twice = mergeLibrarySnapshots([once], fixtures.now);
    assert.equal(summary(twice), summary(once), `${fixture.name}: zweiter Lauf ändert das Ergebnis`);
  }
});

test("Ein einzelner Stand verliert keinen Fortschritt", () => {
  for (const fixture of fixtures.cases) {
    for (const snapshot of fixture.snapshots) {
      const merged = mergeLibrarySnapshots([snapshot], fixtures.now);
      const normalized = normalizedSnapshot(snapshot, fixtures.now);
      const cleared = normalized.sync?.progressClearedAt ?? 0;
      const expected = Object.entries(normalized.progress)
        .filter(([, item]) => item.updatedAt > cleared)
        .map(([key]) => key)
        .sort();
      assert.deepEqual(Object.keys(merged.progress).sort(), expected, `${fixture.name}`);
    }
  }
});

test("Eine kaputte Fremddatei nimmt nur sich selbst mit", () => {
  // Einzelne unbrauchbare Werte werden übergangen, nicht die ganze Datei —
  // und schon gar nicht der lokale Stand.
  const lokal = mergeLibrarySnapshots([{
    version: 6,
    modifiedAt: 1000,
    favorites: ["one-piece"],
    recents: [],
    titles: { "one-piece": "One Piece" },
    progress: {},
    sync: { deviceId: "aaa", favorites: { "aniworld|one-piece": { isFavorite: true, updatedAt: 1000 } } },
  }, {
    // Alles falsch getippt, wie es eine fremde oder kaputte Datei liefern kann.
    version: 6,
    modifiedAt: Number.NaN,
    favorites: ["", "gut"],
    recents: [{ slug: "", title: "x", viewedAt: -5 }],
    titles: { leer: "" },
    progress: { kaputt: { slug: "", episodePath: "", updatedAt: 1 } },
    sync: { deviceId: "bbb", provider: "erfunden" },
  } as unknown as LibraryBag], 2000);

  // Der leere Slug fällt weg, „gut" nicht: eine Datei ohne Sync-Block ist
  // kein Müll, sondern ein Stand aus Schema v5, und ihre Merkliste zählt.
  assert.deepEqual(lokal.favorites.sort(), ["gut", "one-piece"]);
  assert.equal(lokal.titles["one-piece"], "One Piece");
  // Ein Fortschrittseintrag ohne Pfad, ein Verlaufseintrag ohne Slug, ein
  // leerer Titel: einzeln unbrauchbar, einzeln übergangen.
  assert.deepEqual(Object.keys(lokal.progress), []);
  assert.deepEqual(lokal.recents, []);
  assert.equal(lokal.titles.leer, undefined);
  // Ein Provider, den der Enum nicht kennt, setzt die App nicht auf einen
  // unbekannten Zustand.
  assert.ok(lokal.provider === undefined || ["aniworld", "serienstream"].includes(lokal.provider));
});

test("Ein leerer Fremdstand löscht nichts", () => {
  // Der Fall aus der webOS-Einstellung „Bibliothek einlesen": jemand wählt
  // eine leere oder fremde Datei. Ein Einlesen, das den lokalen Stand
  // **ersetzt**, löscht stillschweigend alles, was nur hier stand — und ein
  // Abgleichfehler darf erst recht nichts kosten.
  const lokal: LibraryBag = {
    version: 6,
    modifiedAt: 3000,
    favorites: ["frieren", "dark"],
    favoriteSource: { frieren: "aniworld", dark: "serienstream" },
    favoriteAddedAt: { frieren: 2000, dark: 1000 },
    recents: [{ slug: "frieren", title: "Frieren", viewedAt: 2500, provider: "aniworld" }],
    titles: { frieren: "Frieren" },
    progress: {
      "aniworld|/anime/stream/frieren/staffel-1/episode-1": {
        slug: "frieren", title: "Frieren", season: "1", episode: 1,
        episodePath: "/anime/stream/frieren/staffel-1/episode-1",
        germanTitle: "", englishTitle: "",
        positionSec: 300, durationSec: 1400, updatedAt: 2500,
        provider: "aniworld",
      },
    },
  };

  const leer: LibraryBag = {
    version: 6, modifiedAt: 0, favorites: [], recents: [], titles: {}, progress: {},
  };

  for (const reihenfolge of [[lokal, leer], [leer, lokal]]) {
    const merged = mergeLibrarySnapshots(reihenfolge, 4000);
    assert.deepEqual(merged.favorites.sort(), ["dark", "frieren"]);
    assert.equal(Object.keys(merged.progress).length, 1);
    assert.equal(merged.titles.frieren, "Frieren");
    assert.equal(merged.recents.length, 1);
  }
});

test("Eigene Listen werden zusammengefuehrt, juengster Stand gewinnt", () => {
  const a: LibraryBag = {
    version: 6, modifiedAt: 1000, favorites: [], recents: [], titles: {}, progress: {},
    sync: { deviceId: "deviceA", formatVersion: 1 },
    lists: { isekai: { id: "isekai", name: "Isekai", items: ["aniworld|a"], updatedAt: 1000 } },
  };
  const b: LibraryBag = {
    version: 6, modifiedAt: 2000, favorites: [], recents: [], titles: {}, progress: {},
    sync: { deviceId: "deviceB", formatVersion: 1 },
    lists: { isekai: { id: "isekai", name: "Isekai", items: ["aniworld|b", "aniworld|a"], updatedAt: 2000 } },
  };
  for (const reihenfolge of [[a, b], [b, a]]) {
    const merged = mergeLibrarySnapshots(reihenfolge, 3000);
    assert.equal(merged.lists?.isekai.items.length, 2);
    assert.deepEqual(merged.lists?.isekai.items, ["aniworld|b", "aniworld|a"]);
  }
});

test("Eigene Listen ohne Eintrag fallen beim Abgleich nicht rein", () => {
  const a: LibraryBag = {
    version: 6, modifiedAt: 1000, favorites: [], recents: [], titles: {}, progress: {},
    sync: { deviceId: "deviceA", formatVersion: 1 },
  };
  const merged = mergeLibrarySnapshots([a], 1000);
  assert.deepEqual(merged.lists, {});
});
