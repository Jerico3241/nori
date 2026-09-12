// Der Ablauf eines Abgleichs. Was wann geholt, gerechnet und geschrieben wird.
//
// Die TypeScript-Entsprechung von `LibrarySyncEngine.swift`. Die Aufteilung ist
// dieselbe und aus demselben Grund:
//
//     LibrarySyncHost       kennt die Daten
//     LibrarySyncEngine     kennt den Ablauf
//     LibrarySnapshotStore  kennt die Ablage
//     GoogleDriveClient     kennt HTTP
//     GoogleDeviceAuthorization kennt OAuth
//
// Kein Drive-HTTP in einer React-Komponente, keine OAuth-Logik im
// Bibliothekszustand.

import { LIBRARY_SCHEMA_VERSION, type LibraryBag } from "./library.js";
import { LIBRARY_SYNC_LIMITS, mergeLibrarySnapshots } from "./sync.js";
import { DriveError, GoogleDriveClient, isSnapshot, snapshotName } from "./google/drive.js";

/** Was der Abgleich gerade tut. Gleiches Modell wie im Swift-Kern. */
export type LibrarySyncStatus =
  | "disconnected"
  | "authorizing"
  | "idle"
  | "syncing"
  /** Kein Netz. Kein Fehler, sondern ein Zustand — die Änderungen liegen lokal. */
  | "offline"
  | "error"
  /** In der Cloud liegt ein Stand, den diese Fassung noch nicht kennt. */
  | "unsupportedRemoteVersion";

export interface RemoteSnapshotRef {
  id: string;
  deviceId?: string;
  modifiedTime: string;
  size: number;
}

/** Wohin die Gerätestände gelegt werden. */
export interface LibrarySnapshotStore {
  readonly name: string;
  list(): Promise<RemoteSnapshotRef[]>;
  download(ref: RemoteSnapshotRef): Promise<string>;
  upload(content: string, deviceId: string, fileId: string | null): Promise<RemoteSnapshotRef>;
}

/**
 * Wo sich die Engine merkt, was nicht in die Bibliothek gehört.
 *
 * Die Drive-Dateikennung zum Beispiel: sie gehört zu einem Google-Konto und
 * nicht zu den Daten. Stünde sie in der Bibliothek, wanderte sie beim nächsten
 * Abgleich auf alle anderen Geräte — und die schrieben dann in *diese* Datei.
 */
export interface SyncBookkeeping {
  get(key: string): string | null;
  set(key: string, value: string | null): void;
}

/** Die lokale Bibliothek, von der Engine aus gesehen. */
export interface LibrarySyncHost {
  /** Der Stand **jetzt** — nicht der von vor dem Download. */
  snapshot(): LibraryBag;
  applyMerged(merged: LibraryBag): void;
  readonly deviceId: string;
}

export interface LibrarySyncEngineOptions {
  host: LibrarySyncHost;
  bookkeeping: SyncBookkeeping;
  onChange?: (engine: LibrarySyncEngine) => void;
  now?: () => number;
}

/** Bündelung normaler Änderungen: Merkliste, Einstellungen, Verlauf. */
export const SYNC_DEBOUNCE_MS = 4_000;
/**
 * Während durchgehender Wiedergabe höchstens alle 25 Sekunden.
 *
 * Der Fortschritt wird lokal im Sekundentakt geschrieben — das muss er auch,
 * sonst fehlt nach einem Absturz die letzte Minute. In die Cloud gehört er
 * deshalb noch lange nicht im Sekundentakt.
 */
export const SYNC_PLAYBACK_INTERVAL_MS = 25_000;
/** Wie oft im Vordergrund nach fremden Änderungen gesehen wird. */
export const SYNC_FOREGROUND_POLL_MS = 30_000;

const FILE_ID_KEY = "nori.sync.driveFileId";
const ACCOUNT_KEY = "nori.sync.accountId";

export class LibrarySyncEngine {
  private readonly host: LibrarySyncHost;
  private readonly books: SyncBookkeeping;
  private readonly notify: (engine: LibrarySyncEngine) => void;
  private readonly now: () => number;

  private remote: LibrarySnapshotStore | null = null;
  private running = false;
  private pending = false;
  private debounceTimer: ReturnType<typeof setTimeout> | null = null;
  private pollTimer: ReturnType<typeof setInterval> | null = null;
  private lastUploadAt = 0;
  /** Was schon einmal geholt wurde, nach Dateikennung. */
  private cache = new Map<string, { modifiedTime: string; data: LibraryBag }>();

  status: LibrarySyncStatus = "disconnected";
  lastSuccessfulSync: number | null = null;
  lastError: string | null = null;
  /** Ein einzelner Fremdstand war unlesbar. Kein Grund abzubrechen. */
  lastWarning: string | null = null;
  hasPendingChanges = false;

  constructor(options: LibrarySyncEngineOptions) {
    this.host = options.host;
    this.books = options.bookkeeping;
    this.notify = options.onChange ?? (() => {});
    this.now = options.now ?? (() => Date.now());
  }

  get isConnected(): boolean { return this.remote !== null; }
  get providerName(): string | null { return this.remote?.name ?? null; }

  private setStatus(next: LibrarySyncStatus): void {
    this.status = next;
    this.notify(this);
  }

  /**
   * Eine Ablage anbinden — und sofort abgleichen.
   *
   * **Pull, Merge, Push.** Niemals andersherum: der Fernseher, der sich zum
   * ersten Mal verbindet, darf nicht zuerst seinen eigenen Stand hochladen und
   * damit löschen, was das iPhone dort schon abgelegt hat.
   */
  connect(store: LibrarySnapshotStore, accountId?: string | null): void {
    if (accountId && this.books.get(ACCOUNT_KEY) !== accountId) {
      // Anderes Google-Konto: ein anderer Sync-Raum. Die gemerkte
      // Dateikennung zeigt auf eine Datei, die es dort nicht gibt.
      this.books.set(FILE_ID_KEY, null);
      this.books.set(ACCOUNT_KEY, accountId);
      this.cache.clear();
    }
    this.remote = store;
    this.setStatus("idle");
    void this.run();
  }

  /**
   * Dieses Gerät trennen.
   *
   * Ausdrücklich **nicht**: die Bibliothek löschen, die Drive-Datei löschen
   * oder andere Geräte abmelden.
   */
  disconnect(): void {
    this.clearTimers();
    this.remote = null;
    this.cache.clear();
    this.books.set(FILE_ID_KEY, null);
    this.lastError = null;
    this.lastWarning = null;
    this.setStatus("disconnected");
  }

  setAuthorizing(): void { this.setStatus("authorizing"); }

  setDisconnected(): void {
    if (!this.isConnected) this.setStatus("disconnected");
  }

  // MARK: - Auslöser

  /**
   * Der Zustand hat sich geändert.
   *
   * `duringPlayback` unterscheidet die beiden Takte: ein Häkchen in der
   * Merkliste darf nach ein paar Sekunden oben sein, ein Fortschritt, der im
   * Sekundentakt fortschreibt, nicht.
   */
  noteChange(duringPlayback = false): void {
    if (!this.remote) return;
    this.hasPendingChanges = true;
    if (duringPlayback && this.now() - this.lastUploadAt < SYNC_PLAYBACK_INTERVAL_MS) return;
    this.scheduleSync(duringPlayback ? 0 : SYNC_DEBOUNCE_MS);
  }

  /** Sofort: Pause, Player verlassen, Folge beendet, „Jetzt synchronisieren". */
  syncNow(): void {
    if (this.debounceTimer !== null) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
    void this.run();
  }

  /**
   * Regelmäßig nach fremden Änderungen sehen.
   *
   * Ein Zeitgeber, nicht zehn über die App verteilte. Für Version 1
   * ausdrücklich kein Drive-Changes-Feed: bei vier kleinen Dateien kostet
   * `files.list` weniger als der Aufwand, einen Änderungszeiger zu führen und
   * richtig zu halten.
   */
  startPolling(): void {
    if (this.pollTimer !== null || !this.remote) return;
    this.pollTimer = setInterval(() => { void this.run(); }, SYNC_FOREGROUND_POLL_MS);
  }

  stopPolling(): void {
    if (this.pollTimer === null) return;
    clearInterval(this.pollTimer);
    this.pollTimer = null;
  }

  private clearTimers(): void {
    this.stopPolling();
    if (this.debounceTimer !== null) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
  }

  private scheduleSync(delayMs: number): void {
    if (this.debounceTimer !== null) clearTimeout(this.debounceTimer);
    if (delayMs <= 0) { this.syncNow(); return; }
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = null;
      void this.run();
    }, delayMs);
  }

  // MARK: - Ablauf

  /**
   * Ein vollständiger Abgleich.
   *
   * Läuft schon einer, wird nicht ein zweiter gestartet, sondern gemerkt, dass
   * danach noch einmal gelaufen werden muss. Ohne das entstünden bei fünf
   * schnellen Änderungen fünf parallele Abgleiche, die sich überholen.
   */
  async run(): Promise<void> {
    const remote = this.remote;
    if (!remote) return;
    if (this.running) { this.pending = true; return; }
    this.running = true;

    try {
      this.setStatus("syncing");
      const pulled = await this.pullAndMerge(remote);
      if (!pulled) return;   // Status ist bereits gesetzt

      this.host.applyMerged(pulled.merged);

      // Der eigene Stand wird **nach** dem Anwenden gebildet. Sonst fehlte
      // darin genau das, was gerade zusammengeführt wurde.
      const own = this.host.snapshot();
      const payload = JSON.stringify(own);
      if (payload.length > LIBRARY_SYNC_LIMITS.maxSnapshotBytes) {
        throw new DriveError("tooLarge", `Stand zu groß (${payload.length} Zeichen)`);
      }

      const written = await this.upload(remote, payload, pulled.refs);
      this.books.set(FILE_ID_KEY, written.id);
      // Der eigene Stand ist damit bekannt. Ohne diesen Eintrag lädt der
      // nächste Abgleich die gerade selbst geschriebene Datei wieder herunter.
      this.cache.set(written.id, { modifiedTime: written.modifiedTime, data: own });

      this.lastUploadAt = this.now();
      this.lastSuccessfulSync = this.lastUploadAt;
      this.hasPendingChanges = false;
      this.lastError = null;
      this.setStatus("idle");
    } catch (cause) {
      this.apply(cause);
    } finally {
      this.running = false;
      if (this.pending) {
        this.pending = false;
        void this.run();
      }
    }
  }

  /**
   * Alles holen, was da ist, und mit dem **jetzigen** lokalen Stand verrechnen.
   *
   * „Jetzig" ist der Punkt: zwischen `list()` und hier vergehen Sekunden, und
   * in denen läuft die Wiedergabe weiter. Würde gegen eine Kopie von vorhin
   * zusammengeführt, setzte der Abgleich den Fortschritt zurück, den der
   * Spieler gerade geschrieben hat.
   */
  private async pullAndMerge(
    remote: LibrarySnapshotStore,
  ): Promise<{ merged: LibraryBag; refs: RemoteSnapshotRef[] } | null> {
    const refs = await remote.list();
    const snapshots: LibraryBag[] = [];
    const fresh = new Map<string, { modifiedTime: string; data: LibraryBag }>();
    let warning: string | null = null;

    for (const ref of refs) {
      const cached = this.cache.get(ref.id);
      if (cached && cached.modifiedTime === ref.modifiedTime) {
        fresh.set(ref.id, cached);
        snapshots.push(cached.data);
        continue;
      }
      if (ref.size > LIBRARY_SYNC_LIMITS.maxSnapshotBytes) {
        warning = `Ein Gerätestand ist unerwartet groß (${ref.size} Bytes) und wurde übergangen.`;
        continue;
      }

      let text: string;
      try {
        text = await remote.download(ref);
      } catch (cause) {
        // Zwischen Auflisten und Holen gelöscht. Kein Fehler.
        if (cause instanceof DriveError && cause.kind === "notFound") continue;
        throw cause;
      }

      let decoded: LibraryBag;
      try {
        decoded = JSON.parse(text) as LibraryBag;
        if (!decoded || typeof decoded !== "object") throw new Error("kein Objekt");
      } catch {
        // Eine unlesbare Fremddatei nimmt nur sich selbst mit. Den lokalen
        // Stand mit ihr zu überschreiben wäre der teuerste denkbare Fehler.
        warning = "Ein Gerätestand war nicht lesbar und wurde übergangen.";
        continue;
      }

      if ((decoded.version ?? 1) > LIBRARY_SCHEMA_VERSION) {
        // Eine neuere App hat hier geschrieben. Diese Version würde beim
        // Hochladen Felder wegwerfen, die sie nicht kennt — also wird gar
        // nicht hochgeladen.
        this.lastError = `In der Cloud liegt ein neuerer Stand (Schema ${decoded.version}). Nori muss aktualisiert werden.`;
        this.setStatus("unsupportedRemoteVersion");
        return null;
      }

      fresh.set(ref.id, { modifiedTime: ref.modifiedTime, data: decoded });
      snapshots.push(decoded);
    }

    this.cache = fresh;
    this.lastWarning = warning;
    // Der lokale Stand kommt zuletzt dazu und hat keinen Sonderrang — das
    // Ergebnis ist dasselbe, wenn er zuerst käme.
    return { merged: mergeLibrarySnapshots([...snapshots, this.host.snapshot()], this.now()), refs };
  }

  private async upload(
    remote: LibrarySnapshotStore,
    payload: string,
    refs: RemoteSnapshotRef[],
  ): Promise<RemoteSnapshotRef> {
    // Die gemerkte Kennung zuerst; ist keine da, die eigene Datei am
    // Gerätekennzeichen wiedererkennen. Ohne den zweiten Weg legte jede
    // erneute Zustimmung eine zweite Datei für dasselbe Gerät an.
    const fileId = this.books.get(FILE_ID_KEY)
      ?? refs.find((ref) => ref.deviceId === this.host.deviceId)?.id
      ?? null;
    try {
      return await remote.upload(payload, this.host.deviceId, fileId);
    } catch (cause) {
      if (cause instanceof DriveError && cause.kind === "notFound") {
        this.books.set(FILE_ID_KEY, null);
        return remote.upload(payload, this.host.deviceId, null);
      }
      throw cause;
    }
  }

  private apply(cause: unknown): void {
    if (cause instanceof DriveError) {
      switch (cause.kind) {
        case "notAuthorized":
          this.lastError = "Die Verbindung zu Google ist abgelaufen. Bitte neu verbinden.";
          this.setStatus("error");
          return;
        case "forbidden":
          this.lastError = `Google hat den Zugriff abgelehnt${cause.message ? ` (${cause.message})` : ""}.`;
          this.setStatus("error");
          return;
        case "transport":
          this.lastError = cause.message;
          this.setStatus("offline");
          return;
        case "tooLarge":
          this.lastError = cause.message;
          this.setStatus("error");
          return;
        default:
          this.lastError = cause.message || "Der Abgleich ist fehlgeschlagen.";
          this.setStatus("error");
          return;
      }
    }
    // Netzfehler sehen von hier aus alle gleich aus: nichts ist verloren, es
    // wird später erneut versucht.
    this.lastError = cause instanceof Error ? cause.message : String(cause);
    this.setStatus("offline");
  }
}

/**
 * Die Gerätestände im `appDataFolder`.
 *
 * Dünn mit Absicht: hier steht, *wo* die Dateien liegen und wie sie heißen.
 */
export class GoogleDriveSnapshotStore implements LibrarySnapshotStore {
  readonly name = "Google Drive";

  constructor(private readonly client: GoogleDriveClient) {}

  async list(): Promise<RemoteSnapshotRef[]> {
    const files = await this.client.listSnapshots();
    return files.filter(isSnapshot).map((file) => ({
      id: file.id,
      deviceId: file.deviceId,
      modifiedTime: file.modifiedTime,
      size: file.size,
    }));
  }

  download(ref: RemoteSnapshotRef): Promise<string> {
    return this.client.download(ref.id, ref.size);
  }

  async upload(content: string, deviceId: string, fileId: string | null): Promise<RemoteSnapshotRef> {
    if (fileId) {
      const modifiedTime = await this.client.update(fileId, content);
      return { id: fileId, deviceId, modifiedTime, size: content.length };
    }
    const created = await this.client.create(snapshotName(deviceId), deviceId, content);
    return { id: created.id, deviceId, modifiedTime: created.modifiedTime, size: content.length };
  }
}
