// Die Reihenfolge einer Katalogansicht — gegen nachträglich eintreffende
// TMDB-Angaben. Rein und ohne Netz; die UI-Seite prüft der Fernbedienungstest.

import assert from "node:assert/strict";
import test from "node:test";
import { stableCatalogOrder, type CatalogOrder } from "../src/catalog-order.js";

const VIEW = JSON.stringify(["all", "all", "popular", "all", ""]);
const all = (...ids: string[]) => new Set(ids);

test("Der erste Aufbau übernimmt die frische Sortierung", () => {
  const order = stableCatalogOrder(null, VIEW, ["a", "b", "c", "d"], all("a", "b", "c", "d"));
  assert.deepEqual(order.ids, ["a", "b", "c", "d"]);
});

test("TMDB ändert einen Sortierwert: dieselbe Ansicht bleibt in ihrer Reihenfolge", () => {
  const before = stableCatalogOrder(null, VIEW, ["a", "b", "c", "d"], all("a", "b", "c", "d"));
  // Beliebtheit von D ist eingetroffen — frisch sortiert stünde D vorn.
  const after = stableCatalogOrder(before, VIEW, ["d", "a", "b", "c"], all("a", "b", "c", "d"));
  assert.deepEqual(after.ids, ["a", "b", "c", "d"]);
  assert.equal(after, before, "Ohne Änderung bleibt es dasselbe Objekt");
});

test("Mehrere Antworten in unterschiedlicher Reihenfolge ergeben dieselbe Ansicht", () => {
  const ids = ["a", "b", "c", "d", "e"];
  const start = stableCatalogOrder(null, VIEW, ids, all(...ids));
  const waves = [["e", "a", "b", "c", "d"], ["c", "e", "d", "a", "b"], ["b", "d", "a", "e", "c"]];
  let forward: CatalogOrder = start;
  for (const wave of waves) forward = stableCatalogOrder(forward, VIEW, wave, all(...ids));
  let backward: CatalogOrder = start;
  for (const wave of [...waves].reverse()) backward = stableCatalogOrder(backward, VIEW, wave, all(...ids));
  assert.deepEqual(forward.ids, ids);
  assert.deepEqual(backward.ids, ids);
});

test("Später geladene Titel kommen hinten dazu, ohne Sichtbares zu verschieben", () => {
  const before = stableCatalogOrder(null, VIEW, ["a", "c"], all("a", "c"));
  const after = stableCatalogOrder(before, VIEW, ["b", "a", "d", "c"], all("a", "b", "c", "d"));
  assert.deepEqual(after.ids, ["a", "c", "b", "d"]);
});

test("Ein TMDB-abhängiger Filter wirft eine sichtbare Karte nicht hinaus", () => {
  const before = stableCatalogOrder(null, VIEW, ["a", "b", "c"], all("a", "b", "c", "d"));
  // Nach dem Treffer gilt B nicht mehr als „neu" — die Quelle führt B weiterhin.
  const after = stableCatalogOrder(before, VIEW, ["a", "c"], all("a", "b", "c", "d"));
  assert.deepEqual(after.ids, ["a", "b", "c"]);
});

test("Was die Quelle nicht mehr führt, fällt weg; der Rest behält seine Reihenfolge", () => {
  const before = stableCatalogOrder(null, VIEW, ["a", "b", "c", "d"], all("a", "b", "c", "d"));
  const after = stableCatalogOrder(before, VIEW, ["d", "c", "a"], all("a", "c", "d"));
  assert.deepEqual(after.ids, ["a", "c", "d"]);
});

test("Wechselt die Dubletten-Vertreterin, entsteht keine zweite Karte derselben Serie", () => {
  const ids = ["aniworld|frieren", "serienstream|frieren", "aniworld|one-piece"];
  // Vor TMDB vertritt die Serienstream-Fassung die Serie.
  const before = stableCatalogOrder(null, VIEW, ["serienstream|frieren", "aniworld|one-piece"], all(...ids));
  const groupOf = (id: string) => (id.endsWith("|frieren") ? "frieren" : id);
  // Nach TMDB (Animation) vertritt die AniWorld-Fassung sie.
  const after = stableCatalogOrder(before, VIEW, ["aniworld|frieren", "aniworld|one-piece"], all(...ids), groupOf);
  assert.deepEqual(after.ids, ["serienstream|frieren", "aniworld|one-piece"]);
});

test("Eine bewusst andere Ansicht sortiert neu — Sortierung, Filter, Suche", () => {
  const before = stableCatalogOrder(null, VIEW, ["a", "b", "c"], all("a", "b", "c"));
  const az = JSON.stringify(["all", "all", "az", "all", ""]);
  assert.deepEqual(stableCatalogOrder(before, az, ["c", "a", "b"], all("a", "b", "c")).ids, ["c", "a", "b"]);
  const top = JSON.stringify(["all", "top", "popular", "all", ""]);
  assert.deepEqual(stableCatalogOrder(before, top, ["b"], all("a", "b", "c")).ids, ["b"]);
  const search = JSON.stringify(["all", "all", "popular", "all", "fri"]);
  assert.deepEqual(stableCatalogOrder(before, search, ["c"], all("a", "b", "c")).ids, ["c"]);
});

test("Erneutes Öffnen (ohne bisherige Reihenfolge) nutzt die verbesserte Sortierung", () => {
  const first = stableCatalogOrder(null, VIEW, ["a", "b", "c", "d"], all("a", "b", "c", "d"));
  const stale = stableCatalogOrder(first, VIEW, ["d", "c", "b", "a"], all("a", "b", "c", "d"));
  assert.deepEqual(stale.ids, ["a", "b", "c", "d"]);
  assert.deepEqual(stableCatalogOrder(null, VIEW, ["d", "c", "b", "a"], all("a", "b", "c", "d")).ids, ["d", "c", "b", "a"]);
});

test("Eine leere Ansicht wird beim Eintreffen der Titel aufgebaut, nicht angehängt", () => {
  const empty = stableCatalogOrder(null, VIEW, [], all());
  assert.deepEqual(stableCatalogOrder(empty, VIEW, ["b", "a"], all("a", "b")).ids, ["b", "a"]);
});
