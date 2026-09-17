// Countdown, Quellenwechsel nach einem Fehlschlag und Übersprungmarken.
//
// Dieselben Fälle prüft `native/Tests/NoriCoreTests/PlaybackTests.swift`.

import assert from "node:assert/strict";
import test from "node:test";

import {
  AUTOPLAY_COUNTDOWN_SEC, MAX_AUTOMATIC_SOURCE_SWITCHES, activeSkipSegment, emptyRecovery,
  noteSourceFailure, noteSourceSwitch, planRecovery, recoveryForEpisode, remainingSources,
  sanitizeSkipSegments, shouldOfferNextEpisode, sourceKey,
  type HosterOption, type RecoveryState, type SkipSegment, type SourceRef,
} from "../src/index.js";

function option(name: string, lang = "DE"): HosterOption {
  return { name, lang, langKey: lang, redirectPath: `/redirect/${name}` };
}

const OPTIONS: HosterOption[] = [
  option("Doodstream"), option("VOE"), option("Vidoza"), option("Filemoon"), option("VOE", "EN"),
];

// MARK: - Nächste Folge

test("Der Countdown steht auf zehn Sekunden", () => {
  assert.equal(AUTOPLAY_COUNTDOWN_SEC, 10);
});

test("Der Countdown erscheint erst kurz vor dem Ende", () => {
  assert.equal(shouldOfferNextEpisode(600, 1400, true, true), false);
  assert.equal(shouldOfferNextEpisode(1380, 1400, true, true), true);
});

test("Ohne nächste Folge oder ohne Schalter kein Countdown", () => {
  assert.equal(shouldOfferNextEpisode(1380, 1400, false, true), false);
  assert.equal(shouldOfferNextEpisode(1380, 1400, true, false), false);
});

test("Sehr kurze Stücke bekommen keinen Countdown", () => {
  assert.equal(shouldOfferNextEpisode(18, 19, true, true), false);
});

// MARK: - Wiederherstellung

test("Der erste Fehlschlag wiederholt dieselbe Quelle", () => {
  const current: SourceRef = { hoster: "VOE", lang: "DE" };
  const state = noteSourceFailure(emptyRecovery("aniworld|/a/1"), null);
  assert.deepEqual(planRecovery(state, OPTIONS, current), { kind: "retry" });
});

test("Eine gescheiterte Quelle wird nie wieder angeboten", () => {
  const current: SourceRef = { hoster: "VOE", lang: "DE" };
  const state = noteSourceFailure(emptyRecovery("aniworld|/a/1"), current);
  const step = planRecovery(state, OPTIONS, current);
  assert.equal(step.kind, "switch");
  // Die Rangfolge aus dem Contract gilt weiter: Vidoza vor Filemoon.
  assert.equal(step.kind === "switch" ? step.option.name : "", "Vidoza");
});

test("Zwei kaputte Quellen wechseln sich nicht endlos ab", () => {
  let state: RecoveryState = emptyRecovery("aniworld|/a/1");
  let current: SourceRef = { hoster: "VOE", lang: "DE" };
  for (let round = 0; round < 6; round += 1) {
    state = noteSourceFailure(state, current);
    const step = planRecovery(state, OPTIONS, current);
    if (step.kind === "retry") continue;
    if (step.kind === "switch") {
      state = noteSourceSwitch(state);
      current = { hoster: step.option.name, lang: step.option.lang };
      continue;
    }
    assert.ok(state.switches <= MAX_AUTOMATIC_SOURCE_SWITCHES);
    return;
  }
  assert.fail("Die Wiederherstellung muss nach wenigen Versuchen aufgeben");
});

test("Ohne weitere Quelle wird aufgegeben", () => {
  const current: SourceRef = { hoster: "VOE", lang: "DE" };
  const state = noteSourceFailure(emptyRecovery("aniworld|/a/1"), current);
  const step = planRecovery(state, [option("VOE")], current);
  assert.equal(step.kind, "giveUp");
});

test("Die Restliste bleibt in der laufenden Sprache", () => {
  const state = noteSourceFailure(emptyRecovery("aniworld|/a/1"), { hoster: "VOE", lang: "DE" });
  const left = remainingSources(state, OPTIONS, "DE").map((item) => item.name);
  assert.deepEqual(left, ["Vidoza", "Filemoon", "Doodstream"]);
  // Dieselbe Quelle in einer anderen Sprache ist eine andere Quelle.
  assert.deepEqual(remainingSources(state, OPTIONS, "EN").map((item) => item.name), ["VOE"]);
});

test("Eine neue Folge beginnt von vorn", () => {
  let state = noteSourceFailure(emptyRecovery("aniworld|/a/1"), { hoster: "VOE", lang: "DE" });
  state = noteSourceSwitch(state);
  state = recoveryForEpisode(state, "aniworld|/a/2");
  assert.deepEqual(state.failed, []);
  assert.equal(state.switches, 0);
  assert.equal(remainingSources(state, OPTIONS, "DE")[0].name, "VOE");
});

test("Dieselbe Folge behält ihren Stand", () => {
  let state = noteSourceFailure(emptyRecovery("aniworld|/a/1"), { hoster: "VOE", lang: "DE" });
  state = recoveryForEpisode(state, "aniworld|/a/1");
  assert.equal(state.failed.length, 1);
});

test("Der Quellschlüssel ignoriert Schreibweisen", () => {
  assert.equal(sourceKey({ hoster: "VOE", lang: "DE" }), sourceKey({ hoster: "voe", lang: "de" }));
  assert.notEqual(sourceKey({ hoster: "VOE", lang: "DE" }), sourceKey({ hoster: "VOE", lang: "EN" }));
});

// MARK: - Übersprungmarken

test("Unsinnige Marken fallen weg", () => {
  const raw: SkipSegment[] = [
    { type: "intro", start: -10, end: 90 },
    { type: "outro", start: 1400, end: 1300 },
    { type: "recap", start: 100, end: 101 },
    { type: "outro", start: 1500, end: 1600 },
  ];
  const clean = sanitizeSkipSegments(raw, 1400);
  assert.equal(clean.length, 2);
  assert.deepEqual(clean[0], { type: "intro", start: 0, end: 90 });
  assert.deepEqual(clean[1], { type: "outro", start: 1300, end: 1400 });
});

test("Überlappende Marken derselben Art werden zusammengefasst", () => {
  const clean = sanitizeSkipSegments([
    { type: "intro", start: 0, end: 90 },
    { type: "intro", start: 80, end: 120 },
  ], 1400);
  assert.equal(clean.length, 1);
  assert.equal(clean[0].end, 120);
});

test("Die anliegende Marke an einer Stelle", () => {
  const segments: SkipSegment[] = [{ type: "intro", start: 30, end: 120 }];
  assert.equal(activeSkipSegment(segments, 29), null);
  assert.equal(activeSkipSegment(segments, 30)?.type, "intro");
  assert.equal(activeSkipSegment(segments, 120), null);
});

test("Ohne Daten wird nichts angeboten", () => {
  assert.equal(activeSkipSegment([], 42), null);
  assert.deepEqual(sanitizeSkipSegments([], 1400), []);
});
