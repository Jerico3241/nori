import assert from "node:assert/strict";
import { test } from "node:test";

import {
  episodePathFor, scopeIncludesItem, scopeIncludesProvider, seriesPath,
  type CatalogItem, type WatchProgress,
} from "../src/models.js";
import {
  formatClock, hosterRank, isEpisodeComplete, normalizeEpisodePath, progressKey,
  providerFromPath, resumePosition, watchRatio,
} from "../src/rules.js";
import { orderHosters, pickLang } from "../src/hoster/resolver.js";
import { isAllowedMediaURL, isExternalOrigin, isSafeRemoteURL } from "../src/hoster/safety.js";

function progress(overrides: Partial<WatchProgress> = {}): WatchProgress {
  return {
    slug: "one-piece", title: "One Piece", season: "1", episode: 1,
    episodePath: "/anime/stream/one-piece/staffel-1/episode-1",
    germanTitle: "", englishTitle: "",
    positionSec: 0, durationSec: 1400, updatedAt: 0,
    ...overrides,
  };
}

test("Pfade je Quelle", () => {
  assert.equal(seriesPath("aniworld", "one-piece"), "/anime/stream/one-piece");
  assert.equal(seriesPath("aniworld", "one-piece", "2"), "/anime/stream/one-piece/staffel-2");
  assert.equal(seriesPath("aniworld", "one-piece", "filme"), "/anime/stream/one-piece/filme");
  assert.equal(seriesPath("serienstream", "dexter", "2"), "/serie/dexter/staffel-2");
  assert.equal(episodePathFor("aniworld", "one-piece", "1", 5), "/anime/stream/one-piece/staffel-1/episode-5");
  assert.equal(episodePathFor("serienstream", "dexter", "filme", 2), "/serie/dexter/filme/film-2");
  assert.equal(episodePathFor("aniworld", "one-piece", "", 5), "/anime/stream/one-piece/staffel-1/episode-5");
});

test("Quelle aus dem Pfad", () => {
  assert.equal(providerFromPath("/anime/stream/one-piece/staffel-1/episode-1"), "aniworld");
  assert.equal(providerFromPath("/serie/dexter/staffel-1/episode-1"), "serienstream");
  assert.equal(providerFromPath("/unbekannt"), "aniworld");
});

test("Fortschritt wird nach Quelle und Pfad geschlüsselt", () => {
  assert.equal(normalizeEpisodePath("https://aniworld.to/anime/stream/x/staffel-1/episode-1/"),
    "/anime/stream/x/staffel-1/episode-1");
  assert.equal(progressKey("/serie/dexter/staffel-1/episode-1/", "serienstream"),
    "serienstream|/serie/dexter/staffel-1/episode-1");
  // Dieselbe Serie bei beiden Quellen bleibt getrennt.
  assert.notEqual(
    progressKey("/x/staffel-1/episode-1", "aniworld"),
    progressKey("/x/staffel-1/episode-1", "serienstream"),
  );
});

test("Abschluss- und Resume-Regel aus config/contract.json", () => {
  assert.equal(isEpisodeComplete(progress({ positionSec: 1260, durationSec: 1400 })), true);
  assert.equal(isEpisodeComplete(progress({ positionSec: 1259, durationSec: 1400 })), false);
  assert.equal(isEpisodeComplete(progress({ completed: true, positionSec: 0 })), true);
  // Unter 20 s Dauer greift die 90-%-Regel nicht.
  assert.equal(isEpisodeComplete(progress({ positionSec: 19, durationSec: 19 })), false);
  assert.equal(resumePosition(progress({ positionSec: 7 })), 0);
  assert.equal(resumePosition(progress({ positionSec: 872 })), 872);
  assert.equal(resumePosition(progress({ positionSec: 1399, durationSec: 1400 })), 0);
  assert.equal(watchRatio(progress({ positionSec: 700, durationSec: 1400 })), 0.5);
  assert.equal(watchRatio(null), 0);
});

test("Uhrzeitformat", () => {
  assert.equal(formatClock(0), "0:00");
  assert.equal(formatClock(72), "1:12");
  assert.equal(formatClock(3725), "1:02:05");
  assert.equal(formatClock(-5), "0:00");
});

test("Hoster-Rangfolge und Sprachwahl", () => {
  assert.ok(hosterRank("VOE") < hosterRank("Vidmoly"));
  assert.ok(hosterRank("Vidmoly") < hosterRank("Filemoon"));
  assert.ok(hosterRank("Doodstream") > hosterRank("Unbekannt"));
  const hosters = [
    { name: "Doodstream", lang: "DE", langKey: "1", redirectPath: "/redirect/1" },
    { name: "VOE", lang: "GerSub", langKey: "3", redirectPath: "/redirect/2" },
    { name: "Vidmoly", lang: "DE", langKey: "1", redirectPath: "/redirect/3" },
  ];
  assert.deepEqual(orderHosters(hosters, null).map((h) => h.name), ["VOE", "Vidmoly", "Doodstream"]);
  assert.deepEqual(orderHosters(hosters, "doodstream").map((h) => h.name), ["Doodstream", "VOE", "Vidmoly"]);
  assert.deepEqual(pickLang(hosters, "GerSub").map((h) => h.name), ["VOE"]);
  assert.deepEqual(pickLang(hosters, "EN").map((h) => h.name), ["Doodstream", "Vidmoly"]);
});

test("Adressprüfung blockt lokale und private Netze", () => {
  assert.equal(isSafeRemoteURL("https://voe.sx/e/abc"), true);
  assert.equal(isSafeRemoteURL("http://voe.sx/e/abc"), false);
  assert.equal(isSafeRemoteURL("https://user:pw@voe.sx/e/abc"), false);
  for (const host of [
    "localhost", "127.0.0.1", "10.0.0.5", "192.168.1.1", "172.16.4.4",
    "169.254.169.254", "100.64.0.1", "0.0.0.0", "224.0.0.1", "nas.local",
  ]) {
    assert.equal(isSafeRemoteURL(`https://${host}/x.m3u8`), false, host);
  }
  assert.equal(isAllowedMediaURL("https://cdn.example/stream/index.m3u8"), true);
  assert.equal(isAllowedMediaURL("https://cdn.example/seite.html"), false);
  assert.equal(isAllowedMediaURL("https://127.0.0.1/index.m3u8"), false);
  assert.equal(isExternalOrigin("https://voe.sx/e/x"), true);
  assert.equal(isExternalOrigin("https://aniworld.to/redirect/1"), false);
  assert.equal(isExternalOrigin("https://serienstream.to/r?t=1"), false);
});

test("Bereich filtert nach Quelle und Genre", () => {
  const kdrama: CatalogItem = {
    slug: "a", title: "A", alts: [], genres: ["K-Drama"], provider: "serienstream",
  };
  const serie: CatalogItem = {
    slug: "b", title: "B", alts: [], genres: ["Drama"], provider: "serienstream",
  };
  const anime: CatalogItem = { slug: "c", title: "C", alts: [], genres: [], provider: "aniworld" };
  assert.equal(scopeIncludesItem("kdrama", kdrama), true);
  assert.equal(scopeIncludesItem("kdrama", serie), false);
  assert.equal(scopeIncludesItem("kdrama", anime), false);
  assert.equal(scopeIncludesItem("all", anime), true);
  assert.equal(scopeIncludesItem("serienstream", serie), true);
  // Einträge ohne Quelle stammen aus älteren Ständen und fallen nicht raus.
  assert.equal(scopeIncludesProvider("aniworld", null), true);
});
