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
  LibrarySyncEngine, type LibrarySnapshotStore, type LibrarySyncHost, type RemoteSnapshotRef, type SyncBookkeeping,
} from "../src/sync-engine.js";

/** Eine Ablage im Arbeitsspeicher — viele Dateien, je eine pro Gerät. */
class FakeStore implements LibrarySnapshotStore {
  readonly name = "Testablage";
  files = new Map<string, { deviceId: string; modifiedTime: number; content: string }>();
  listError: Error | null = null;
  uploads = 0;
  downloads = 0;
  private clock = 0;
  private next = 0;

  async list(): Promise<RemoteSnapshotRef[]> {
    if (this.listError) throw this.listError;
    return [...this.files.entries()]
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
    const id = `file-${this.next}`;
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
