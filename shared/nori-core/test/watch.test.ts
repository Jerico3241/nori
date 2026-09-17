// „Gesehen", „ungesehen" und „aus Weiterschauen entfernen".
//
// Dieselben Fälle prüft `native/Tests/NoriCoreTests/WatchMarksTests.swift` für
// den Swift-Kern. Weichen die beiden ab, zeigt der Fernseher auf denselben
// Drive-Daten einen anderen Stand als das iPhone.

import assert from "node:assert/strict";
import test from "node:test";

import {
  continueWatching, isEpisodeComplete, markEpisode, markSeason, markSeries,
  removeFromContinueWatching, resetSeasonProgress, resetSeriesProgress,
  seasonProgressLabel, seriesWatchSummary, watchStateText, watchSummary,
  type Episode, type MarkTarget, type WatchProgress,
} from "../src/index.js";

const PROVIDER = "aniworld" as const;

function path(season: string, number: number): string {
  return `/anime/stream/demo/staffel-${season}/episode-${number}`;
}

function episode(number: number, season = "1"): Episode {
  return {
    number,
    germanTitle: `Folge ${number}`,
    englishTitle: `Episode ${number}`,
    path: path(season, number),
    hosters: [],
    languages: [],
  };
}

function entry(
  number: number,
  positionSec: number,
  durationSec: number,
  extra: Partial<WatchProgress> = {},
): WatchProgress {
  const season = extra.season ?? "1";
  return {
    slug: "demo",
    title: "Demo",
    season,
    episode: number,
    episodePath: path(season, number),
    germanTitle: `Folge ${number}`,
    englishTitle: `Episode ${number}`,
    positionSec,
    durationSec,
    updatedAt: 1_000,
    lang: "DE",
    provider: PROVIDER,
    ...extra,
  };
}

function store(items: WatchProgress[]): Record<string, WatchProgress> {
  const out: Record<string, WatchProgress> = {};
  for (const item of items) out[`${item.provider}|${item.episodePath}`] = item;
  return out;
}

const target: MarkTarget = { slug: "demo", title: "Demo", season: "1", provider: PROVIDER };

test("Als gesehen markieren behält die bekannte Laufzeit", () => {
  const progress = store([entry(1, 300, 1400)]);
  const marked = markEpisode(progress, target, episode(1), true, 9000);
  assert.equal(isEpisodeComplete(marked), true);
  assert.equal(marked.durationSec, 1400);
  assert.equal(marked.positionSec, 1400);
  assert.equal(marked.updatedAt, 9000);
  assert.equal(marked.lang, "DE");
});

test("Eine unbekannte Folge lässt sich auch ohne Laufzeit abhaken", () => {
  const marked = markEpisode({}, target, episode(3), true, 9000);
  assert.equal(isEpisodeComplete(marked), true);
  assert.equal(marked.durationSec, 0);
  assert.equal(marked.episodePath, path("1", 3));
});

test("Als ungesehen markieren schreibt einen leeren Stand statt zu löschen", () => {
  const progress = store([entry(1, 1400, 1400, { completed: true })]);
  const marked = markEpisode(progress, target, episode(1), false, 9000);
  assert.equal(isEpisodeComplete(marked), false);
  assert.equal(marked.positionSec, 0);
  // Die Laufzeit ist eine Auskunft und geht nicht verloren.
  assert.equal(marked.durationSec, 1400);
  assert.equal(marked.updatedAt, 9000);
  assert.equal(watchSummary([marked]).state, "unseen");
});

test("Der Zeitstempel steht in Millisekunden", () => {
  const before = Date.now();
  const marked = markEpisode({}, target, episode(1), true);
  assert.ok(marked.updatedAt >= before);
  assert.ok(marked.updatedAt < before + 60_000);
});

test("Eine Staffel wird vollständig abgehakt", () => {
  const episodes = [1, 2, 3, 4].map((n) => episode(n));
  const marked = markSeason({}, target, episodes, true, 5);
  assert.equal(marked.length, 4);
  assert.ok(marked.every((item) => isEpisodeComplete(item)));
});

test("Eine Serie deckt jede übergebene Staffel ab", () => {
  const marked = markSeries({}, { slug: "demo", title: "Demo", provider: PROVIDER }, [
    { season: "1", episodes: [episode(1), episode(2)] },
    { season: "2", episodes: [episode(1, "2")] },
  ], true, 5);
  assert.equal(marked.length, 3);
  assert.deepEqual([...new Set(marked.map((item) => item.season))].sort(), ["1", "2"]);
});

test("Serie zurücksetzen braucht keine Folgenliste und damit kein Netz", () => {
  const progress = store([
    entry(1, 1400, 1400, { completed: true }),
    entry(2, 120, 1400),
    entry(3, 0, 0),
  ]);
  const reset = resetSeriesProgress(progress, "demo", PROVIDER, 9000);
  // Der nie angefasste Eintrag braucht keine Marke.
  assert.equal(reset.length, 2);
  assert.ok(reset.every((item) => item.positionSec === 0 && item.completed === false));
  assert.ok(reset.every((item) => item.updatedAt === 9000));
});

test("Eine Staffel zurücksetzen lässt die anderen stehen", () => {
  const progress = store([
    entry(1, 600, 1400, { season: "1" }),
    entry(1, 600, 1400, { season: "2", episodePath: path("2", 1) }),
  ]);
  const reset = resetSeasonProgress(progress, "demo", "2", PROVIDER, 9000);
  assert.equal(reset.length, 1);
  assert.equal(reset[0].season, "2");
});

test("Marken laufen nie über Quellgrenzen", () => {
  const progress = store([
    entry(1, 600, 1400),
    entry(1, 600, 1400, { provider: "serienstream", episodePath: "/serie/demo/staffel-1/episode-1" }),
  ]);
  const reset = resetSeriesProgress(progress, "demo", "serienstream", 9000);
  assert.equal(reset.length, 1);
  assert.equal(reset[0].provider, "serienstream");
});

test("Aus Weiterschauen entfernen behält abgeschlossene Folgen", () => {
  const progress = store([
    entry(1, 1400, 1400, { completed: true }),
    entry(2, 300, 1400),
  ]);
  const touched = removeFromContinueWatching(progress, "demo", PROVIDER, 9000);
  assert.equal(touched.length, 1);
  assert.equal(touched[0].episode, 2);
  assert.equal(touched[0].positionSec, 0);

  // Und die Serie steht danach nicht mehr in der Reihe.
  const after = { ...progress };
  for (const item of touched) after[`${item.provider}|${item.episodePath}`] = item;
  assert.equal(continueWatching(after).length, 0);
});

test("Ein nur geöffneter Eintrag zählt nicht als Weiterschauen", () => {
  const progress = store([entry(1, 0, 1400)]);
  assert.equal(continueWatching(progress).length, 0);
});

test("Eine halb gesehene Folge bleibt, wenn danach nur geöffnet wurde", () => {
  const progress = store([
    entry(2, 600, 1400, { updatedAt: 10 }),
    entry(3, 0, 1400, { updatedAt: 20 }),
  ]);
  const list = continueWatching(progress);
  assert.equal(list.length, 1);
  assert.equal(list[0].episode, 2);
});

test("Der Sehstand einer Serie folgt derselben Regel wie die Merkliste", () => {
  const started = store([entry(1, 1400, 1400, { completed: true }), entry(2, 300, 1400)]);
  assert.equal(seriesWatchSummary(started, "demo", PROVIDER).state, "started");
  assert.equal(seriesWatchSummary(started, "demo", PROVIDER).completedEpisodes, 1);

  const seen = store([entry(1, 1400, 1400, { completed: true })]);
  assert.equal(seriesWatchSummary(seen, "demo", PROVIDER).state, "seen");
  assert.equal(seriesWatchSummary({}, "demo", PROVIDER).state, "unseen");
});

test("Die Zeile unter dem Titel nennt Staffel, Folge und Anteil", () => {
  const summary = watchSummary([entry(7, 700, 1400, { season: "2" })]);
  assert.equal(watchStateText(summary), "S2 · F7 · 50 %");
  assert.equal(watchStateText(watchSummary([])), "Noch nicht begonnen");
  assert.equal(
    watchStateText(watchSummary([entry(1, 1400, 1400, { completed: true })])),
    "Komplett gesehen",
  );
});

test("Fortschritt einer Staffel als Text", () => {
  assert.equal(seasonProgressLabel(7, 12), "7 von 12 gesehen");
  assert.equal(seasonProgressLabel(0, 12), null);
  assert.equal(seasonProgressLabel(0, 0), null);
});
