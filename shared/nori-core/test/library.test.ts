import assert from "node:assert/strict";
import { test } from "node:test";

import type { Episode, WatchProgress } from "../src/models.js";
import {
  continueWatching, decodeLibrary, encodeLibrary, findProgress, migrateProgress,
  nextEpisode, nextPlay, previousEpisode, rememberRecent, seasonStats, upsertProgress,
} from "../src/library.js";

function item(overrides: Partial<WatchProgress> = {}): WatchProgress {
  return {
    slug: "one-piece", title: "One Piece", season: "1", episode: 1,
    episodePath: "/anime/stream/one-piece/staffel-1/episode-1",
    germanTitle: "", englishTitle: "",
    positionSec: 100, durationSec: 1400, updatedAt: 1000,
    ...overrides,
  };
}

function episodes(count: number): Episode[] {
  return Array.from({ length: count }, (_, i) => ({
    number: i + 1,
    germanTitle: `Folge ${i + 1}`,
    englishTitle: "",
    path: `/anime/stream/one-piece/staffel-1/episode-${i + 1}`,
    hosters: [],
    languages: [],
  }));
}

test("v1-Stände werden auf provider|Pfad umgeschlüsselt, jüngster gewinnt", () => {
  const old = {
    "/anime/stream/one-piece/staffel-1/episode-1": item({ positionSec: 10, updatedAt: 1 }),
    "/anime/stream/one-piece/staffel-1/episode-1|DE": item({ positionSec: 500, updatedAt: 9 }),
    "/anime/stream/one-piece/staffel-1/episode-1/": item({ positionSec: 20, updatedAt: 5 }),
  };
  const migrated = migrateProgress(old as Record<string, WatchProgress>);
  assert.equal(Object.keys(migrated).length, 1);
  const key = "aniworld|/anime/stream/one-piece/staffel-1/episode-1";
  assert.equal(migrated[key].positionSec, 500);
  assert.equal(migrated[key].provider, "aniworld");
});

test("upsert setzt completed ab 90 % und räumt alte Schlüssel weg", () => {
  let progress: Record<string, WatchProgress> = {
    "/anime/stream/one-piece/staffel-1/episode-1": item({ positionSec: 10 }),
  };
  progress = upsertProgress(progress, item({ positionSec: 1300, durationSec: 1400 }));
  assert.equal(Object.keys(progress).length, 1);
  const stored = progress["aniworld|/anime/stream/one-piece/staffel-1/episode-1"];
  assert.equal(stored.completed, true);
  assert.equal(stored.provider, "aniworld");
});

test("Dieselbe Serie bei beiden Quellen bleibt getrennt", () => {
  let progress: Record<string, WatchProgress> = {};
  progress = upsertProgress(progress, item({ positionSec: 100 }));
  progress = upsertProgress(progress, item({
    provider: "serienstream",
    episodePath: "/serie/one-piece/staffel-1/episode-1",
    positionSec: 900,
  }));
  assert.equal(Object.keys(progress).length, 2);
  assert.equal(findProgress(progress, "/anime/stream/one-piece/staffel-1/episode-1", "aniworld")?.positionSec, 100);
  assert.equal(findProgress(progress, "/serie/one-piece/staffel-1/episode-1", "serienstream")?.positionSec, 900);
});

test("Weiterschauen zeigt je Serie den jüngsten unfertigen Eintrag", () => {
  const progress: Record<string, WatchProgress> = {};
  for (const p of [
    item({ episode: 1, episodePath: "/anime/stream/a/staffel-1/episode-1", slug: "a", positionSec: 1390, durationSec: 1400, updatedAt: 5 }),
    item({ episode: 2, episodePath: "/anime/stream/a/staffel-1/episode-2", slug: "a", positionSec: 200, updatedAt: 9 }),
    item({ episode: 1, episodePath: "/anime/stream/b/staffel-1/episode-1", slug: "b", positionSec: 300, updatedAt: 7 }),
  ]) {
    progress[`aniworld|${p.episodePath}`] = p;
  }
  const list = continueWatching(progress);
  assert.deepEqual(list.map((i) => `${i.slug}#${i.episode}`), ["a#2", "b#1"]);
});

test("nextPlay: erstes Öffnen spielt, angefangene Folge wird fortgesetzt", () => {
  const eps = episodes(5);
  assert.deepEqual(nextPlay({}, "one-piece", "1", eps, "aniworld", true),
    { episode: 1, resumeAt: 0, kind: "play" });

  const started: Record<string, WatchProgress> = {
    "aniworld|/anime/stream/one-piece/staffel-1/episode-2":
      item({ episode: 2, episodePath: "/anime/stream/one-piece/staffel-1/episode-2", positionSec: 400, updatedAt: 10 }),
  };
  assert.deepEqual(nextPlay(started, "one-piece", "1", eps, "aniworld", true),
    { episode: 2, resumeAt: 400, kind: "resume" });
  // Ohne Resume wird dieselbe Folge von vorn gespielt.
  assert.deepEqual(nextPlay(started, "one-piece", "1", eps, "aniworld", false),
    { episode: 2, resumeAt: 0, kind: "play" });

  const finishedFirst: Record<string, WatchProgress> = {
    "aniworld|/anime/stream/one-piece/staffel-1/episode-1":
      item({ episode: 1, positionSec: 1400, durationSec: 1400, updatedAt: 10, completed: true }),
  };
  assert.deepEqual(nextPlay(finishedFirst, "one-piece", "1", eps, "aniworld", true),
    { episode: 2, resumeAt: 0, kind: "next" });
});

test("Staffelstatistik und Folgenreihenfolge", () => {
  const eps = episodes(4);
  const progress: Record<string, WatchProgress> = {
    "aniworld|/anime/stream/one-piece/staffel-1/episode-1":
      item({ episode: 1, completed: true }),
    "aniworld|/anime/stream/one-piece/staffel-1/episode-2":
      item({ episode: 2, episodePath: "/anime/stream/one-piece/staffel-1/episode-2", positionSec: 1400, durationSec: 1400 }),
  };
  assert.deepEqual(seasonStats(progress, "one-piece", "1", eps, "aniworld"),
    { watched: 2, total: 4, pct: 50 });
  assert.equal(nextEpisode(eps[0], eps)?.number, 2);
  assert.equal(nextEpisode(eps[3], eps), null);
  assert.equal(previousEpisode(eps[2], eps)?.number, 2);
  assert.equal(previousEpisode(eps[0], eps), null);
});

test("Bibliothek überlebt einen Umlauf durch encode/decode", () => {
  const state = decodeLibrary({
    version: 1,
    favorites: ["one-piece"],
    recents: [{ slug: "one-piece", title: "One Piece", viewedAt: 5 }],
    titles: { "one-piece": "One Piece" },
    progress: { "/anime/stream/one-piece/staffel-1/episode-1": item() },
    langPref: "GerSub",
    hosterPref: "Vidmoly",
    // Unbekannte Schlüssel älterer Stände dürfen nicht stören.
    cloudSyncEnabled: true,
  });
  assert.equal(state.langPref, "GerSub");
  assert.equal(state.hosterPref, "Vidmoly");
  assert.equal(state.scope, "all");
  assert.equal(state.resumeEnabled, true);
  const bag = encodeLibrary(state);
  assert.equal(bag.version, 4);
  const again = decodeLibrary(bag);
  assert.deepEqual(again.progress, state.progress);
  assert.deepEqual(again.favorites, state.favorites);
});

test("Verlauf hält höchstens 100 Einträge und schiebt den jüngsten nach vorn", () => {
  let recents = rememberRecent([], "a", "A", "aniworld");
  recents = rememberRecent(recents, "b", "B", "aniworld");
  recents = rememberRecent(recents, "a", "A", "serienstream");
  assert.deepEqual(recents.map((r) => r.slug), ["a", "b"]);
  assert.equal(recents[0].provider, "serienstream");
  for (let i = 0; i < 120; i += 1) recents = rememberRecent(recents, `s${i}`, "X", "aniworld");
  assert.equal(recents.length, 100);
});
