// Der Ablauf eines Abgleichs auf webOS — ohne Google, ohne Netz.
//
// Dieselben Fälle wie `LibrarySyncEngineTests.swift`. Geprüft werden
// Reihenfolge, Wiederholung und Fehlerbehandlung: Entscheidungen im Nori-Code
// und keine Eigenschaften von Drive.

import assert from "node:assert/strict";
import test from "node:test";
import { emptyLibrary, encodeLibrary, decodeLibrary, LIBRARY_SCHEMA_VERSION, type LibraryBag, type LibraryState } from "../src/library.js";
import { favoriteKey } from "../src/sync.js";
import {
  DriveError, GoogleDriveClient, retryDelay, DEFAULT_RETRY_POLICY, snapshotName, isSnapshot,
} from "../src/google/drive.js";
import {
  candidateGroups, LibrarySyncEngine, type LibrarySnapshotStore, type LibrarySyncHost, type RemoteSnapshotRef, type SyncBookkeeping,
} from "../src/sync-engine.js";
import {
  DRIVE_FILE_SCOPE, DRIVE_SPACES, driveSpaceProperties, driveSpaceQuery,
} from "../src/google/drive.js";
import { sha256Hex } from "../src/hash.js";
import { createHash } from "node:crypto";
import { GoogleAuthError } from "../src/google/auth.js";

/** Eine Ablage im Arbeitsspeicher — viele Dateien, je eine pro Gerät. */
class FakeStore implements LibrarySnapshotStore {
  readonly name = "Testablage";
  /** Eigene Kennungen je Ablage — sonst fiele eine verwechselte Kennung nicht auf. */
  constructor(private readonly prefix = "file") {}
  files = new Map<string, { deviceId: string; modifiedTime: number; content: string }>();
  listError: Error | null = null;
  uploads = 0;
  downloads = 0;
  private clock = 0;
  private next = 0;

  /** Im Papierkorb: noch vorhanden, aber von der Suche (`trashed=false`) nicht gefunden. */
  trashed = new Set<string>();

  async list(): Promise<RemoteSnapshotRef[]> {
    if (this.listError) throw this.listError;
    return [...this.files.entries()]
      .filter(([id]) => !this.trashed.has(id))
      .map(([id, file]) => ({ id, deviceId: file.deviceId, modifiedTime: String(file.modifiedTime), size: file.content.length }))
      .sort((a, b) => (a.id < b.id ? -1 : 1));
  }

  async download(ref: RemoteSnapshotRef): Promise<string> {
    this.downloads += 1;
    const file = this.files.get(ref.id);
    if (!file) throw new DriveError("notFound", "weg");
    return file.content;
  }

  async upload(content: string, deviceId: string, fileId: string | null): Promise<RemoteSnapshotRef> {
    this.uploads += 1;
    this.clock += 1;
    if (fileId) {
      if (!this.files.has(fileId)) throw new DriveError("notFound", "weg");
      this.files.set(fileId, { deviceId, modifiedTime: this.clock, content });
      return { id: fileId, deviceId, modifiedTime: String(this.clock), size: content.length };
    }
    this.next += 1;
    const id = `${this.prefix}-${this.next}`;
    this.files.set(id, { deviceId, modifiedTime: this.clock, content });
    return { id, deviceId, modifiedTime: String(this.clock), size: content.length };
  }

  seed(id: string, deviceId: string, content: string): void {
    this.clock += 1;
    this.files.set(id, { deviceId, modifiedTime: this.clock, content });
  }
}

class FakeBooks implements SyncBookkeeping {
  values = new Map<string, string>();
  get(key: string): string | null { return this.values.get(key) ?? null; }
  set(key: string, value: string | null): void {
    if (value === null) this.values.delete(key); else this.values.set(key, value);
  }
}

/** Eine lokale Bibliothek, wie der webOS-Zustand sie hält. */
class FakeHost implements LibrarySyncHost {
  state: LibraryState;
  constructor(readonly deviceId: string, seed?: Partial<LibraryState>) {
    this.state = { ...emptyLibrary(), deviceId, ...seed };
  }
  snapshot(): LibraryBag { return encodeLibrary(this.state); }
  applyMerged(merged: LibraryBag): void {
    const decoded = decodeLibrary(merged);
    // Die eigene Kennung gehört zur Installation, nicht zu den Daten.
    this.state = { ...decoded, deviceId: this.deviceId };
  }
}

function engineFor(host: FakeHost, store: FakeStore, books = new FakeBooks()) {
  const engine = new LibrarySyncEngine({ host, bookkeeping: books });
  // `connect` würde nebenher abgleichen; die Tests warten lieber ab.
  (engine as unknown as { remote: LibrarySnapshotStore }).remote = store;
  engine.status = "idle";
  return { engine, books };
}

function favorite(host: FakeHost, slug: string, at: number): void {
  host.state = {
    ...host.state,
    favorites: [slug, ...host.state.favorites],
    favoriteSource: { ...host.state.favoriteSource, [slug]: "aniworld" },
    favoriteAddedAt: { ...host.state.favoriteAddedAt, [slug]: at },
    titles: { ...host.state.titles, [slug]: slug },
    favoriteMarks: {
      ...host.state.favoriteMarks,
      [favoriteKey(slug, "aniworld")]: { isFavorite: true, updatedAt: at, addedAt: at },
    },
    modifiedAt: at,
  };
}

function unfavorite(host: FakeHost, slug: string, at: number): void {
  host.state = {
    ...host.state,
    favorites: host.state.favorites.filter((s) => s !== slug),
    favoriteMarks: {
      ...host.state.favoriteMarks,
      [favoriteKey(slug, "aniworld")]: { isFavorite: false, updatedAt: at },
    },
    modifiedAt: at,
  };
}

// --- B: erstes Gerät --------------------------------------------------------

test("Erstes Gerät lädt seine Bibliothek hoch", async () => {
  const host = new FakeHost("tv");
  favorite(host, "one-piece", 1000);
  const store = new FakeStore();
  const { engine, books } = engineFor(host, store);

  await engine.run();

  assert.equal(store.files.size, 1);
  const uploaded = JSON.parse([...store.files.values()][0].content) as LibraryBag;
  assert.deepEqual(uploaded.favorites, ["one-piece"]);
  assert.equal(uploaded.sync?.deviceId, "tv");
  assert.ok(books.get("nori.sync.driveFileId"));
  assert.equal(engine.status, "idle");
});

test("Der zweite Lauf überschreibt statt anzulegen", async () => {
  const host = new FakeHost("tv");
  favorite(host, "one-piece", 1000);
  const store = new FakeStore();
  const { engine } = engineFor(host, store);

  await engine.run();
  favorite(host, "naruto", 2000);
  await engine.run();

  assert.equal(store.files.size, 1, "Bei jedem Abgleich eine neue Datei — der Ordner liefe voll.");
  assert.equal(store.uploads, 2);
});

// --- C: zweites Gerät -------------------------------------------------------

test("Ein frisches Gerät übernimmt den Stand aus der Cloud", async () => {
  const quelle = new FakeHost("iphone");
  favorite(quelle, "one-piece", 1000);
  const store = new FakeStore();
  store.seed("fremd", "iphone", JSON.stringify(quelle.snapshot()));

  const neu = new FakeHost("tv");
  const { engine } = engineFor(neu, store);
  await engine.run();

  assert.deepEqual(neu.state.favorites, ["one-piece"]);
  // Und der Stand des anderen Geräts liegt unverändert daneben.
  const fremd = JSON.parse(store.files.get("fremd")!.content) as LibraryBag;
  assert.deepEqual(fremd.favorites, ["one-piece"]);
});

// --- E: Grabsteine über den ganzen Weg --------------------------------------

test("Ein entfernter Titel bleibt entfernt, auch wenn das andere Gerät alt ist", async () => {
  const store = new FakeStore();
  const a = new FakeHost("aaa");
  const b = new FakeHost("bbb");
  const { engine: syncA } = engineFor(a, store);
  const { engine: syncB } = engineFor(b, store);

  favorite(a, "one-piece", 1000);
  await syncA.run();
  await syncB.run();
  assert.deepEqual(b.state.favorites, ["one-piece"]);

  unfavorite(a, "one-piece", 5000);
  await syncA.run();
  await syncB.run();

  assert.deepEqual(b.state.favorites, [], "Der Grabstein hat nicht gehalten");
  await syncA.run();
  assert.deepEqual(a.state.favorites, [], "B hat den Titel wieder hingelegt");
});

// --- J: offline -------------------------------------------------------------

test("Ohne Netz bleibt die Bibliothek unangetastet", async () => {
  const host = new FakeHost("tv");
  favorite(host, "one-piece", 1000);
  const store = new FakeStore();
  store.listError = new DriveError("transport", "Kein Netz");
  const { engine } = engineFor(host, store);

  await engine.run();

  assert.equal(engine.status, "offline");
  assert.deepEqual(host.state.favorites, ["one-piece"], "Ein Netzfehler hat die Bibliothek angefasst");

  store.listError = null;
  await engine.run();
  assert.equal(engine.status, "idle");
  assert.equal(store.files.size, 1);
});

// --- K: die Berechtigung gilt nicht mehr ------------------------------------
//
// Ein eigener Zustand und kein Fehler. Vorher landete das bei „Fehler" mit
// einem Satz daneben, oder — schlimmer — bei „offline", weil die abgelaufene
// Berechtigung aus der Autorisierungsschicht kommt und nicht als `DriveError`.
// Die Oberfläche wartete dann auf ein Netz, das längst da war.

test("Eine abgelaufene Berechtigung verlangt eine Anmeldung, keinen Fehlertext", async () => {
  const host = new FakeHost("tv");
  favorite(host, "one-piece", 1000);
  const store = new FakeStore();
  store.listError = new DriveError("notAuthorized", "Nicht mehr autorisiert");
  const { engine } = engineFor(host, store);

  await engine.run();

  assert.equal(engine.status, "needsReauthorization");
  assert.equal(engine.lastError, null, "Ein technischer Text, wo eine Handlung gehört");
  assert.deepEqual(host.state.favorites, ["one-piece"], "Die Bibliothek wurde angefasst");
});

test("Auch ein Fehler aus der Autorisierung selbst landet dort", async () => {
  const host = new FakeHost("tv");
  const store = new FakeStore();
  // So kommt es aus `GoogleDeviceAuthorization`, bevor überhaupt eine Anfrage
  // hinausgeht: der Auffrischungstoken gilt nicht mehr.
  store.listError = new GoogleAuthError("notAuthorized", "Die Verbindung zu Google ist abgelaufen.");
  const { engine } = engineFor(host, store);

  await engine.run();

  assert.equal(engine.status, "needsReauthorization");
  assert.equal(engine.lastError, null);
});

// --- L: kaputter Fremdstand -------------------------------------------------

test("Eine unlesbare Fremddatei nimmt nur sich selbst mit", async () => {
  const host = new FakeHost("tv");
  favorite(host, "one-piece", 1000);
  const gut = new FakeHost("mac");
  favorite(gut, "naruto", 1000);

  const store = new FakeStore();
  store.seed("kaputt", "xxx", "{ das ist kein JSON");
  store.seed("gut", "mac", JSON.stringify(gut.snapshot()));

  const { engine } = engineFor(host, store);
  await engine.run();

  assert.equal(engine.status, "idle", "Ein kaputter Fremdstand hat den Abgleich abgebrochen");
  assert.ok(engine.lastWarning);
  assert.deepEqual([...host.state.favorites].sort(), ["naruto", "one-piece"]);
});

// --- M: neuere Schemaversion ------------------------------------------------

test("Eine ältere App überschreibt keinen neueren Stand", async () => {
  const host = new FakeHost("tv");
  favorite(host, "one-piece", 1000);
  const zukunft = { ...host.snapshot(), version: LIBRARY_SCHEMA_VERSION + 1 };

  const store = new FakeStore();
  store.seed("neuer", "zzz", JSON.stringify(zukunft));

  const { engine } = engineFor(host, store);
  await engine.run();

  assert.equal(engine.status, "unsupportedRemoteVersion");
  assert.equal(store.uploads, 0, "Eine ältere App hat einen neueren Stand überschrieben");
  assert.deepEqual(host.state.favorites, ["one-piece"], "Die lokale Bibliothek ist trotzdem benutzbar");
});

// --- Wiedererkennung und Zwischenspeicher -----------------------------------

test("Die eigene Datei wird am Gerätekennzeichen wiedererkannt", async () => {
  const host = new FakeHost("tv");
  favorite(host, "one-piece", 1000);
  const store = new FakeStore();
  const { engine, books } = engineFor(host, store);

  await engine.run();
  assert.equal(store.files.size, 1);

  // Wie nach einer erneuten Zustimmung.
  books.set("nori.sync.driveFileId", null);
  favorite(host, "naruto", 2000);
  await engine.run();

  assert.equal(store.files.size, 1, "Für dasselbe Gerät liegen jetzt zwei Dateien in Drive");
});

test("Unveränderte Fremdstände werden nicht erneut geladen", async () => {
  const anderes = new FakeHost("mac");
  favorite(anderes, "naruto", 1000);
  const store = new FakeStore();
  store.seed("anderes", "mac", JSON.stringify(anderes.snapshot()));

  const host = new FakeHost("tv");
  const { engine } = engineFor(host, store);
  await engine.run();
  const nachErstem = store.downloads;
  await engine.run();

  assert.equal(store.downloads, nachErstem, "Ein unveränderter Fremdstand wurde erneut geladen");
});

test("Zeigt die gemerkte Dateikennung ins Leere, wird eine neue angelegt", async () => {
  const host = new FakeHost("tv");
  const store = new FakeStore();
  const books = new FakeBooks();
  books.set("nori.sync.driveFileId", "gibt-es-nicht");
  const { engine } = engineFor(host, store, books);

  await engine.run();

  assert.equal(store.files.size, 1);
  assert.notEqual(books.get("nori.sync.driveFileId"), "gibt-es-nicht");
});

test("Trennen lässt Bibliothek und Drive-Datei in Ruhe", async () => {
  const host = new FakeHost("tv");
  favorite(host, "one-piece", 1000);
  const store = new FakeStore();
  const { engine } = engineFor(host, store);
  await engine.run();

  engine.disconnect();

  assert.equal(engine.status, "disconnected");
  assert.equal(engine.isConnected, false);
  assert.deepEqual(host.state.favorites, ["one-piece"]);
  assert.equal(store.files.size, 1, "Trennen hat die Drive-Datei gelöscht");
});

// --- Der Drive-Client -------------------------------------------------------

class ScriptedFetch {
  calls: { url: string; init: RequestInit }[] = [];
  constructor(private script: { status: number; body: string }[]) {}
  readonly fetchImpl: typeof fetch = (async (url: string | URL | Request, init: RequestInit = {}) => {
    this.calls.push({ url: String(url), init });
    const next = this.script.shift() ?? { status: 200, body: "{}" };
    return new Response(next.body, { status: next.status });
  }) as unknown as typeof fetch;
  get authHeaders(): string[] {
    return this.calls.map((call) => (call.init.headers as Record<string, string>)?.Authorization ?? "");
  }
}

class CountingAuth {
  refreshes = 0;
  private issued = 1;
  async validAccessToken(): Promise<string> { return `token-${this.issued}`; }
  async refreshAccessToken(): Promise<string> {
    this.refreshes += 1;
    this.issued += 1;
    return `token-${this.issued}`;
  }
}

function clientFor(script: ScriptedFetch, auth: CountingAuth, delays: number[] = []) {
  return new GoogleDriveClient({
    authorization: auth,
    fetchImpl: script.fetchImpl,
    sleep: async (ms) => { delays.push(ms); },
    random: () => 0.5,
  });
}

test("Ein abgelaufenes Token wird genau einmal erneuert", async () => {
  const script = new ScriptedFetch([{ status: 401, body: "{}" }, { status: 200, body: '{"files":[]}' }]);
  const auth = new CountingAuth();

  const files = await clientFor(script, auth).listSnapshots();

  assert.deepEqual(files, []);
  assert.equal(auth.refreshes, 1);
  assert.deepEqual(script.authHeaders, ["Bearer token-1", "Bearer token-2"]);
});

test("Zweimal 401 heißt aufgeben, nicht weiter erneuern", async () => {
  const script = new ScriptedFetch([{ status: 401, body: "{}" }, { status: 401, body: "{}" }]);
  const auth = new CountingAuth();

  await assert.rejects(() => clientFor(script, auth).listSnapshots(), (error: DriveError) => {
    assert.equal(error.kind, "notAuthorized");
    return true;
  });
  assert.equal(script.calls.length, 2, "Endlosschleife gegen Googles Rate Limit");
});

test("429 bekommt Backoff und läuft danach durch", async () => {
  const script = new ScriptedFetch([
    { status: 429, body: "{}" }, { status: 429, body: "{}" }, { status: 200, body: '{"files":[]}' },
  ]);
  const delays: number[] = [];

  await clientFor(script, new CountingAuth(), delays).listSnapshots();

  assert.equal(script.calls.length, 3);
  assert.deepEqual(delays, [1000, 2000]);
});

test("Der Aufschub wird gestreut und bleibt unter der Obergrenze", () => {
  assert.equal(Math.round(retryDelay(DEFAULT_RETRY_POLICY, 0, 0)), 700);
  assert.equal(Math.round(retryDelay(DEFAULT_RETRY_POLICY, 0, 1)), 1300);
  assert.ok(retryDelay(DEFAULT_RETRY_POLICY, 20, 1) <= DEFAULT_RETRY_POLICY.maxDelayMs * 1.3);
});

test("Eine entzogene Berechtigung wird nicht erneut versucht", async () => {
  const script = new ScriptedFetch([
    { status: 403, body: '{"error":{"errors":[{"reason":"insufficientPermissions"}]}}' },
    { status: 200, body: '{"files":[]}' },
  ]);

  await assert.rejects(() => clientFor(script, new CountingAuth()).listSnapshots(), (error: DriveError) => {
    assert.equal(error.kind, "forbidden");
    return true;
  });
  assert.equal(script.calls.length, 1);
});

test("Ein als 403 getarntes Rate Limit wird wiederholt", async () => {
  const script = new ScriptedFetch([
    { status: 403, body: '{"error":{"errors":[{"reason":"userRateLimitExceeded"}]}}' },
    { status: 200, body: '{"files":[]}' },
  ]);

  await clientFor(script, new CountingAuth()).listSnapshots();

  assert.equal(script.calls.length, 2);
});

test("Das Verzeichnis bleibt im versteckten Ordner", async () => {
  const script = new ScriptedFetch([{ status: 200, body: '{"files":[]}' }]);
  await clientFor(script, new CountingAuth()).listSnapshots();
  assert.ok(script.calls[0].url.includes("spaces=appDataFolder"), script.calls[0].url);
});

test("Der Upload legt die Datei im versteckten Ordner an", async () => {
  const script = new ScriptedFetch([{ status: 200, body: '{"id":"neu","modifiedTime":"jetzt"}' }]);
  const created = await clientFor(script, new CountingAuth())
    .create(snapshotName("abc"), "abc", '{"favorites":[]}');

  assert.equal(created.id, "neu");
  const body = String(script.calls[0].init.body);
  assert.ok(body.includes("appDataFolder"));
  assert.ok(body.includes("nori-sync-v1-abc.json"));
  assert.ok(body.includes('"deviceId":"abc"'));
});

test("Zu große Dateien werden gar nicht erst geholt", async () => {
  const script = new ScriptedFetch([{ status: 200, body: "{}" }]);
  await assert.rejects(
    () => clientFor(script, new CountingAuth()).download("riesig", 99_000_000),
    (error: DriveError) => { assert.equal(error.kind, "tooLarge"); return true; },
  );
  assert.equal(script.calls.length, 0, "Die Datei wurde trotzdem angefragt");
});

test("Nori fordert genau einen Bereich an", async () => {
  const { DRIVE_APPDATA_SCOPE } = await import("../src/google/drive.js");
  assert.equal(DRIVE_APPDATA_SCOPE, "https://www.googleapis.com/auth/drive.appdata");
});

test("Nori-Dateien werden am Namen oder an der Kennung erkannt", () => {
  assert.equal(isSnapshot({ id: "1", name: "nori-sync-v1-abc.json", modifiedTime: "", size: 0 }), true);
  assert.equal(isSnapshot({ id: "2", name: "irgendwas.txt", modifiedTime: "", size: 0 }), false);
  assert.equal(isSnapshot({ id: "3", name: "irgendwas.txt", modifiedTime: "", size: 0, deviceId: "abc" }), true);
});

// --- Zwei Ablagen: appDataFolder und TV-Spiegel ------------------------------

const MIRROR_PREFIX = "nori.sync.tvMirror";

function engineWith(host: FakeHost, store: FakeStore, books: FakeBooks, keyPrefix?: string, onMergedChange?: () => void) {
  const engine = new LibrarySyncEngine({ host, bookkeeping: books, keyPrefix, onMergedChange });
  (engine as unknown as { remote: LibrarySnapshotStore }).remote = store;
  engine.status = "idle";
  return engine;
}

test("SHA-256 ohne WebCrypto stimmt mit Node überein — auch ohne TextEncoder", () => {
  const samples = [
    "", "abc", "Grüße aus Köln – „Nori“ 🍥", "x".repeat(55), "x".repeat(56), "y".repeat(64),
    JSON.stringify({ favorites: Array.from({ length: 300 }, (_, i) => `titel-${i}`) }),
  ];
  // Der Prüfvektor aus FIPS 180-2, in Stücken: `check-webos-package.py` hält
  // lange Hex-Zeichenketten im Quelltext für Schlüssel.
  const abc = ["ba7816bf8f01cfea", "414140de5dae2223", "b00361a396177a9c", "b410ff61f20015ad"].join("");
  assert.equal(sha256Hex("abc"), abc);
  const expected = samples.map((sample) => createHash("sha256").update(sample, "utf8").digest("hex"));
  assert.deepEqual(samples.map(sha256Hex), expected);

  // webOS 6 hat TextEncoder — ältere Umgebungen nicht zwingend.
  const scope = globalThis as unknown as { TextEncoder?: unknown };
  const saved = scope.TextEncoder;
  scope.TextEncoder = undefined;
  try {
    assert.deepEqual(samples.map(sha256Hex), expected, "Der Rückfall ohne TextEncoder rechnet anders");
  } finally {
    scope.TextEncoder = saved;
  }
});

test("Zwei Ablagen, getrennt benannt und gekennzeichnet", () => {
  assert.equal(snapshotName("abc"), "nori-sync-v1-abc.json");
  assert.equal(snapshotName("abc", 1, "tvMirror"), "nori-tv-sync-v1-abc.json");
  assert.equal(driveSpaceQuery("appData"), null);
  const query = driveSpaceQuery("tvMirror") ?? "";
  assert.ok(query.includes("value='library-mirror'") && query.includes("trashed=false"), query);
  assert.ok(!/name|parents/.test(query), "Erkannt wird nie an Name oder Ordner");
  assert.deepEqual(driveSpaceProperties("tvMirror", "abc"),
    { app: "nori", type: "library-mirror", syncVersion: "1", deviceId: "abc", mirror: "tv" });
  assert.deepEqual(driveSpaceProperties("appData", "abc"),
    { app: "nori", type: "library-snapshot", syncVersion: "1", deviceId: "abc" });
  assert.equal(DRIVE_FILE_SCOPE, "https://www.googleapis.com/auth/drive.file");
  assert.equal(DRIVE_SPACES.appData.visible, false);
  assert.equal(DRIVE_SPACES.tvMirror.visible, true);
});

function mirrorClientFor(script: ScriptedFetch) {
  return new GoogleDriveClient({
    authorization: new CountingAuth(), fetchImpl: script.fetchImpl,
    sleep: async () => {}, random: () => 0.5, space: "tvMirror",
  });
}

const decodedUrl = (url: string) => decodeURIComponent(url.replace(/\+/g, " "));

test("Der Spiegel wird über appProperties gelistet — umbenannt und verschoben gefunden", async () => {
  const script = new ScriptedFetch([{ status: 200, body: JSON.stringify({ files: [{
    id: "m1", name: "Von Hand umbenannt.json", modifiedTime: "2026-09-13T01:00:00.000Z", size: "10",
    appProperties: { app: "nori", type: "library-mirror", deviceId: "mac", mirror: "tv" },
  }] }) }]);

  const files = await mirrorClientFor(script).listSnapshots();

  assert.deepEqual(files.map((file) => file.id), ["m1"]);
  const url = decodedUrl(script.calls[0].url);
  assert.ok(url.includes("spaces=drive"), url);
  assert.ok(!url.includes("appDataFolder"), url);
  assert.ok(url.includes("value='library-mirror'"), url);
});

test("Eine Spiegeldatei landet im ältesten Nori-Ordner, nie im appDataFolder", async () => {
  const script = new ScriptedFetch([
    { status: 200, body: JSON.stringify({ files: [
      { id: "neuer", createdTime: "2026-09-13T00:00:00.000Z" }, { id: "aelter", createdTime: "2026-09-01T00:00:00.000Z" },
    ] }) },
    { status: 200, body: '{"id":"datei","modifiedTime":"jetzt"}' },
  ]);

  const created = await mirrorClientFor(script).create(snapshotName("abc", 1, "tvMirror"), "abc", "{}");

  assert.equal(created.id, "datei");
  assert.equal(script.calls.length, 2);
  assert.ok(decodedUrl(script.calls[0].url).includes("value='mirror-folder'"));
  const body = String(script.calls[1].init.body);
  assert.ok(body.includes('"parents":["aelter"]'), body.slice(0, 300));
  assert.ok(!body.includes("appDataFolder"));
  assert.ok(body.includes("nori-tv-sync-v1-abc.json") && body.includes('"mirror":"tv"') && body.includes('"library-mirror"'));
});

test("Fehlt der Nori-Ordner, wird er angelegt", async () => {
  const script = new ScriptedFetch([
    { status: 200, body: '{"files":[]}' },
    { status: 200, body: '{"id":"ordner"}' },
    { status: 200, body: '{"id":"datei","modifiedTime":"jetzt"}' },
  ]);

  await mirrorClientFor(script).create(snapshotName("abc", 1, "tvMirror"), "abc", "{}");

  assert.equal(script.calls.length, 3);
  const folder = String(script.calls[1].init.body);
  assert.ok(folder.includes("application/vnd.google-apps.folder") && folder.includes('"mirror-folder"') && folder.includes('"Nori"'), folder);
  assert.ok(String(script.calls[2].init.body).includes('"parents":["ordner"]'));
});

test("Scheitert der Ordner, wird die Spiegeldatei trotzdem geschrieben", async () => {
  const script = new ScriptedFetch([
    { status: 403, body: '{"error":{"errors":[{"reason":"insufficientPermissions"}]}}' },
    { status: 200, body: '{"id":"datei","modifiedTime":"jetzt"}' },
  ]);

  const created = await mirrorClientFor(script).create(snapshotName("abc", 1, "tvMirror"), "abc", "{}");

  assert.equal(created.id, "datei");
  assert.equal(script.calls.length, 2);
  assert.ok(!String(script.calls[1].init.body).includes("appDataFolder"));
});

test("Der appDataFolder fragt nie nach einem Ordner", async () => {
  const script = new ScriptedFetch([{ status: 200, body: '{"id":"neu","modifiedTime":"jetzt"}' }]);
  await clientFor(script, new CountingAuth()).create(snapshotName("abc"), "abc", "{}");
  assert.equal(script.calls.length, 1);
});

test("Fehlt drive.file, antwortet der Spiegel mit forbidden und wird nicht wiederholt", async () => {
  const script = new ScriptedFetch([
    { status: 403, body: '{"error":{"errors":[{"reason":"insufficientScopes"}]}}' },
    { status: 200, body: '{"files":[]}' },
  ]);
  await assert.rejects(() => mirrorClientFor(script).listSnapshots(), (error: DriveError) => {
    assert.equal(error.kind, "forbidden");
    return true;
  });
  assert.equal(script.calls.length, 1);
});

test("Jede Ablage führt eigene Merkposten — keine Kennung wandert hinüber", async () => {
  const host = new FakeHost("mac");
  favorite(host, "one-piece", 1000);
  const books = new FakeBooks();
  const cloud = new FakeStore("appdata");
  const mirror = new FakeStore("mirror");
  const app = engineWith(host, cloud, books);
  const tv = engineWith(host, mirror, books, MIRROR_PREFIX);

  await app.run();
  await tv.run();

  assert.ok(books.get("nori.sync.driveFileId")?.startsWith("appdata-"));
  assert.ok(books.get("nori.sync.tvMirror.driveFileId")?.startsWith("mirror-"));
  assert.ok(books.get("nori.sync.lastUpload"));
  assert.ok(books.get("nori.sync.tvMirror.lastUpload"));

  tv.disconnect();
  assert.equal(books.get("nori.sync.tvMirror.driveFileId"), null);
  assert.ok(books.get("nori.sync.driveFileId"), "Ausschalten des Spiegels hat den appDataFolder vergessen");

  // Eine hineingeschmuggelte Kennung des appDataFolder führt nicht dorthin.
  books.set("nori.sync.tvMirror.driveFileId", books.get("nori.sync.driveFileId"));
  (tv as unknown as { remote: LibrarySnapshotStore }).remote = mirror;
  tv.status = "idle";
  favorite(host, "naruto", 2000);
  await tv.run();

  assert.equal(cloud.uploads, 1, "Der Spiegel hat in den appDataFolder geschrieben");
  assert.equal(mirror.files.size, 1);
  assert.ok([...mirror.files.keys()].every((id) => id.startsWith("mirror-")));
});

test("Nach einem Neustart ohne Änderung wird nichts geschrieben", async () => {
  const host = new FakeHost("tv");
  favorite(host, "one-piece", 1000);
  const store = new FakeStore();
  const books = new FakeBooks();

  await engineFor(host, store, books).engine.run();
  assert.equal(store.uploads, 1);

  await engineFor(host, store, books).engine.run();
  assert.equal(store.uploads, 1, "Der unveränderte Stand wurde nach dem Neustart erneut geschrieben");

  // Anderswo verändert: wieder schreiben.
  const own = books.get("nori.sync.driveFileId") ?? "";
  store.seed(own, "tv", store.files.get(own)?.content ?? "");
  await engineFor(host, store, books).engine.run();
  assert.equal(store.uploads, 2);

  favorite(host, "naruto", 2000);
  await engineFor(host, store, books).engine.run();
  assert.equal(store.uploads, 3);
  assert.equal(store.files.size, 1);
});

test("Der Fernseher schreibt seine unveränderte Datei nicht bei jedem Abgleich neu", async () => {
  const host = new FakeHost("tv");
  favorite(host, "one-piece", 1000);
  const store = new FakeStore("mirror");
  const engine = engineWith(host, store, new FakeBooks(), MIRROR_PREFIX);
  for (let i = 0; i < 10; i += 1) await engine.run();
  assert.equal(store.uploads, 1, "Im Proof of Concept: 27 Updates in 17 Minuten");
});

test("Doppelte Dateien eines Geräts: die neueste gilt, nichts wird gelöscht", async () => {
  const older = new FakeHost("mac");
  favorite(older, "alt", 1000);
  const newer = new FakeHost("mac");
  favorite(newer, "neu", 2000);
  const store = new FakeStore("mirror");
  store.seed("z-alt", "mac", JSON.stringify(older.snapshot()));
  store.seed("a-neu", "mac", JSON.stringify(newer.snapshot()));
  const host = new FakeHost("tv");
  const { engine } = engineFor(host, store);

  await engine.run();

  assert.deepEqual(host.state.favorites, ["neu"]);
  assert.equal(store.downloads, 1, "Die überzählige Datei wurde trotzdem geladen");
  assert.equal(store.files.size, 3, "Nori hat eine Datei gelöscht");
  assert.equal(engine.remoteDeviceCount, 1);
  assert.ok(engine.lastWarning?.includes("mehrere Dateien"), engine.lastWarning ?? "keine Warnung");
});

test("Doppelte eigene Dateien: die neueste wird beschrieben, keine dritte angelegt", async () => {
  const host = new FakeHost("tv");
  favorite(host, "one-piece", 1000);
  const store = new FakeStore();
  store.seed("eigen-alt", "tv", JSON.stringify(host.snapshot()));
  store.seed("eigen-neu", "tv", JSON.stringify(host.snapshot()));
  const { engine, books } = engineFor(host, store);
  favorite(host, "naruto", 2000);

  await engine.run();

  assert.equal(store.files.size, 2);
  assert.equal(books.get("nori.sync.driveFileId"), "eigen-neu");
  assert.equal(store.files.get("eigen-alt")?.modifiedTime, 1, "Die ältere Datei wurde angefasst");
});

test("Eine eigene Spiegeldatei im Papierkorb wird ersetzt, nicht weiter beschrieben", async () => {
  const host = new FakeHost("tv");
  favorite(host, "one-piece", 1000);
  const store = new FakeStore("mirror");
  const books = new FakeBooks();
  const engine = engineWith(host, store, books, MIRROR_PREFIX);
  await engine.run();
  const first = books.get("nori.sync.tvMirror.driveFileId") ?? "";

  store.trashed.add(first);
  await engine.run();

  const second = books.get("nori.sync.tvMirror.driveFileId");
  assert.notEqual(second, first, "Die Datei im Papierkorb wurde weiter beschrieben");
  assert.equal(store.uploads, 2);
  assert.ok(store.files.has(first), "Nori hat die Datei im Papierkorb gelöscht");
});

test("Relais: iPhone → Mac → Fernseher und zurück, samt Entfernung", async () => {
  const cloud = new FakeStore("appdata");
  const mirror = new FakeStore("mirror");
  const iphone = new FakeHost("iphone");
  const mac = new FakeHost("mac");
  const tv = new FakeHost("tv");
  const macBooks = new FakeBooks();
  const log: string[] = [];
  const iphoneEngine = engineWith(iphone, cloud, new FakeBooks());
  const macApp = engineWith(mac, cloud, macBooks, undefined, () => log.push("zum Spiegel"));
  const macMirror = engineWith(mac, mirror, macBooks, MIRROR_PREFIX, () => log.push("zum appDataFolder"));
  const tvEngine = engineWith(tv, mirror, new FakeBooks(), MIRROR_PREFIX);

  favorite(iphone, "naruto", 1000);
  await iphoneEngine.run();
  await macApp.run();
  assert.deepEqual(log, ["zum Spiegel"]);
  await macMirror.run();
  await tvEngine.run();
  assert.deepEqual(tv.state.favorites, ["naruto"], "Die Merkliste des iPhones kam nicht am Fernseher an");

  favorite(tv, "one-piece", 2000);
  await tvEngine.run();
  await macMirror.run();
  assert.equal(log[log.length - 1], "zum appDataFolder");
  await macApp.run();
  await iphoneEngine.run();
  assert.deepEqual([...iphone.state.favorites].sort(), ["naruto", "one-piece"]);

  unfavorite(iphone, "naruto", 3000);
  await iphoneEngine.run();
  await macApp.run();
  await macMirror.run();
  await tvEngine.run();
  assert.deepEqual(tv.state.favorites, ["one-piece"], "Die Entfernung kam am Fernseher nicht an");

  assert.deepEqual([...new Set([...cloud.files.values()].map((file) => file.deviceId))].sort(), ["iphone", "mac"]);
  assert.deepEqual([...new Set([...mirror.files.values()].map((file) => file.deviceId))].sort(), ["mac", "tv"]);
  assert.ok([...cloud.files.keys()].every((id) => id.startsWith("appdata-")));
  assert.ok([...mirror.files.keys()].every((id) => id.startsWith("mirror-")));
  assert.equal(tvEngine.remoteDeviceCount, 1);
});

test("Nur ein veränderter Stand stößt die andere Ablage an", async () => {
  const host = new FakeHost("mac");
  favorite(host, "one-piece", 1000);
  const store = new FakeStore();
  let calls = 0;
  const engine = engineWith(host, store, new FakeBooks(), undefined, () => { calls += 1; });

  // Der erste Abgleich darf einmalig fehlende Einstellungsmarken ergänzen
  // (`updatedAt` = `modifiedAt`) — danach ist der Stand stabil.
  await engine.run();
  const initial = calls;
  assert.ok(initial <= 1, `${initial} Meldungen beim ersten Abgleich`);
  await engine.run();
  assert.equal(calls, initial, "Ein unveränderter Stand hat die andere Ablage erneut angestoßen");

  const other = new FakeHost("iphone");
  favorite(other, "naruto", 2000);
  store.seed("iphone-datei", "iphone", JSON.stringify(other.snapshot()));
  await engine.run();
  assert.equal(calls, initial + 1);

  await engine.run();
  await engine.run();
  assert.equal(calls, initial + 1, "Ohne neue Änderung wurde die andere Ablage erneut angestoßen");
});

test("Kein Apple-Gerät im Spiegel: remoteDeviceCount ist 0, mit mehreren zählt jedes einmal", async () => {
  const host = new FakeHost("tv");
  const store = new FakeStore("mirror");
  const engine = engineWith(host, store, new FakeBooks(), MIRROR_PREFIX);
  assert.equal(engine.remoteDeviceCount, null);

  await engine.run();
  assert.equal(engine.remoteDeviceCount, 0);

  for (const name of ["iphone", "ipad", "mac"]) {
    const other = new FakeHost(name);
    favorite(other, name, 1000);
    store.seed(`${name}-datei`, name, JSON.stringify(other.snapshot()));
  }
  await engine.run();
  assert.equal(engine.remoteDeviceCount, 3);
  assert.deepEqual([...host.state.favorites].sort(), ["ipad", "iphone", "mac"]);
});

test("Zwei Abgleiche zugleich legen keine zweite Datei an", async () => {
  const host = new FakeHost("tv");
  favorite(host, "one-piece", 1000);
  const store = new FakeStore();
  const { engine } = engineFor(host, store);

  await Promise.all([engine.run(), engine.run(), engine.run()]);
  await new Promise((resolve) => setTimeout(resolve, 20));

  assert.equal(store.files.size, 1);
  assert.equal(store.uploads, 1);
});

test("Fehler im TV-Spiegel bleiben im Spiegel", async () => {
  const host = new FakeHost("mac");
  favorite(host, "one-piece", 1000);
  const books = new FakeBooks();
  const cloud = new FakeStore("appdata");
  const mirror = new FakeStore("mirror");
  const app = engineWith(host, cloud, books);
  const tv = engineWith(host, mirror, books, MIRROR_PREFIX);

  mirror.listError = new DriveError("notAuthorized", "weg");
  await tv.run();
  assert.equal(tv.status, "needsReauthorization");

  mirror.listError = new DriveError("forbidden", "insufficientScopes", 403);
  await tv.run();
  assert.equal(tv.status, "error");
  assert.ok(tv.lastError?.includes("insufficientScopes"));

  mirror.listError = new DriveError("http", "Rate Limit", 429);
  await tv.run();
  assert.notEqual(tv.status, "idle");

  mirror.listError = new DriveError("transport", "Kein Netz");
  await tv.run();
  assert.equal(tv.status, "offline");

  await app.run();
  assert.equal(app.status, "idle", "Ein Fehler im Spiegel hat den appDataFolder aufgehalten");
  assert.equal(cloud.files.size, 1);
  assert.equal(mirror.files.size, 0);
  assert.deepEqual(host.state.favorites, ["one-piece"]);

  mirror.listError = null;
  await tv.run();
  assert.equal(tv.status, "idle");
  assert.equal(mirror.files.size, 1);
});

test("Die Lesereihenfolge hängt nicht an Drives Reihenfolge", () => {
  const refs: RemoteSnapshotRef[] = [
    { id: "b", deviceId: "mac", modifiedTime: "2026-09-13T10:00:00.000Z", size: 1 },
    { id: "a", deviceId: "mac", modifiedTime: "2026-09-13T11:00:00.000Z", size: 1 },
    { id: "c", deviceId: "iphone", modifiedTime: "2026-09-13T09:00:00.000Z", size: 1 },
    { id: "z", modifiedTime: "2026-09-13T08:00:00.000Z", size: 1 },
    { id: "d", deviceId: "mac", modifiedTime: "2026-09-13T11:00:00.000Z", size: 1 },
  ];
  const expected = [["c"], ["d", "a", "b"], ["z"]];
  assert.deepEqual(candidateGroups(refs).map((group) => group.map((ref) => ref.id)), expected);
  assert.deepEqual(candidateGroups([...refs].reverse()).map((group) => group.map((ref) => ref.id)), expected);
});
