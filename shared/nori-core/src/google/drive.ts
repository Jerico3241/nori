// Google Drive, aber nur der versteckte `appDataFolder`.
//
// Die TypeScript-Entsprechung von `GoogleDrive.swift`: dieselben Endpunkte,
// dieselben Wiederholungsregeln, dieselben Grenzen. Was hier steht, ist HTTP
// und sonst nichts — keine Anmeldung, keine Bibliothek, keine Oberfläche.
//
// Der `appDataFolder` ist ein versteckter Ordner je App und Konto. Der Nutzer
// sieht ihn in „Meine Ablage" nicht, andere Apps kommen nicht heran, und mit
// der App verschwindet er. Nori braucht deshalb genau einen Bereich — den
// kleinsten, der reicht.

import { LIBRARY_SYNC_LIMITS } from "../sync.js";

export const DRIVE_APPDATA_SCOPE = "https://www.googleapis.com/auth/drive.appdata";

const FILES_ENDPOINT = "https://www.googleapis.com/drive/v3/files";
const UPLOAD_ENDPOINT = "https://www.googleapis.com/upload/drive/v3/files";

export type DriveErrorKind =
  | "notAuthorized"
  | "forbidden"
  | "notFound"
  | "conflict"
  | "http"
  | "transport"
  | "tooLarge";

export class DriveError extends Error {
  constructor(readonly kind: DriveErrorKind, message: string, readonly status = 0) {
    super(message);
    this.name = "DriveError";
  }

  get isRetryable(): boolean {
    if (this.kind === "transport") return true;
    return this.kind === "http" && (this.status === 429 || (this.status >= 500 && this.status < 600));
  }
}

export interface DriveFile {
  id: string;
  name: string;
  /** RFC-3339, wie Drive es liefert. Wird nur verglichen, nicht gerechnet. */
  modifiedTime: string;
  size: number;
  deviceId?: string;
}

/**
 * Wie oft und wie lange wiederholt wird — an einer Stelle und nicht in jedem
 * Aufruf. Sonst hat jeder Endpunkt seine eigene Schleife, und eine davon läuft
 * endlos.
 */
export interface DriveRetryPolicy {
  maxAttempts: number;
  baseDelayMs: number;
  maxDelayMs: number;
  /** Streuung, damit vier Geräte nach einem `429` nicht im Gleichschritt zurückkommen. */
  jitter: number;
}

export const DEFAULT_RETRY_POLICY: DriveRetryPolicy = {
  maxAttempts: 5,
  baseDelayMs: 1_000,
  maxDelayMs: 16_000,
  jitter: 0.3,
};

export function retryDelay(policy: DriveRetryPolicy, attempt: number, random: number): number {
  const raw = Math.min(policy.maxDelayMs, policy.baseDelayMs * 2 ** attempt);
  return raw * (1 - policy.jitter + 2 * policy.jitter * random);
}

/** Der Dateiname eines Gerätestands. */
export function snapshotName(deviceId: string, formatVersion = 1): string {
  return `nori-sync-v${formatVersion}-${deviceId}.json`;
}

/**
 * Gehört die Datei zu Nori?
 *
 * `appProperties` zuerst, Name als Rückfall. Der Ordner ist zwar ausschließlich
 * Noris, aber eine ältere oder von Hand abgelegte Datei darf den Abgleich nicht
 * durcheinanderbringen.
 */
export function isSnapshot(file: DriveFile): boolean {
  if (file.deviceId) return true;
  return file.name.startsWith("nori-sync-v") && file.name.endsWith(".json");
}

/** Woher das Zugriffstoken kommt. */
export interface DriveAuthorization {
  validAccessToken(): Promise<string>;
  refreshAccessToken(): Promise<string>;
}

export interface GoogleDriveClientOptions {
  authorization: DriveAuthorization;
  fetchImpl?: typeof fetch;
  policy?: DriveRetryPolicy;
  /** Nur für Tests — sonst dauerte ein Backoff-Test echte 31 Sekunden. */
  sleep?: (ms: number) => Promise<void>;
  random?: () => number;
}

export class GoogleDriveClient {
  private readonly authorization: DriveAuthorization;
  private readonly fetchImpl: typeof fetch;
  private readonly policy: DriveRetryPolicy;
  private readonly sleep: (ms: number) => Promise<void>;
  private readonly random: () => number;

  constructor(options: GoogleDriveClientOptions) {
    this.authorization = options.authorization;
    this.fetchImpl = options.fetchImpl ?? ((...args) => fetch(...args));
    this.policy = options.policy ?? DEFAULT_RETRY_POLICY;
    this.sleep = options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
    this.random = options.random ?? Math.random;
  }

  /**
   * Alles, was im `appDataFolder` liegt.
   *
   * Ohne Suchausdruck: der Ordner gehört ausschließlich Nori. Ein `q=`-Ausdruck
   * wäre eine zusätzliche Stelle, an der sich Drive-Syntax ändern kann, ohne
   * etwas dafür zu leisten.
   */
  async listSnapshots(): Promise<DriveFile[]> {
    const url = `${FILES_ENDPOINT}?${new URLSearchParams({
      spaces: "appDataFolder",
      pageSize: "100",
      fields: "files(id,name,modifiedTime,size,appProperties)",
    })}`;
    const response = await this.perform(url, { method: "GET" });
    const body = (await response.json()) as { files?: unknown[] };
    if (!Array.isArray(body.files)) throw new DriveError("http", "Verzeichnis nicht lesbar", 200);
    return body.files.flatMap((raw) => {
      const entry = raw as Record<string, unknown>;
      if (typeof entry.id !== "string" || typeof entry.name !== "string") return [];
      const properties = entry.appProperties as Record<string, string> | undefined;
      return [{
        id: entry.id,
        name: entry.name,
        modifiedTime: typeof entry.modifiedTime === "string" ? entry.modifiedTime : "",
        // Drive liefert `size` als Zeichenkette — es ist ein int64.
        size: Number(entry.size ?? 0) || 0,
        deviceId: properties?.deviceId,
      }];
    });
  }

  /**
   * Den Inhalt einer Datei holen.
   *
   * `expectedSize` kommt aus dem Verzeichnis und wird **vorher** geprüft. Eine
   * Bibliothek ist ein paar Kilobyte groß; was um Größenordnungen darüber
   * liegt, wird nicht heruntergeladen, sondern gemeldet.
   */
  async download(id: string, expectedSize?: number): Promise<string> {
    if (expectedSize !== undefined && expectedSize > LIBRARY_SYNC_LIMITS.maxSnapshotBytes) {
      throw new DriveError("tooLarge", `Datei zu groß (${expectedSize} Bytes)`);
    }
    const response = await this.perform(`${FILES_ENDPOINT}/${encodeURIComponent(id)}?alt=media`, { method: "GET" });
    const text = await response.text();
    if (text.length > LIBRARY_SYNC_LIMITS.maxSnapshotBytes) {
      throw new DriveError("tooLarge", `Datei zu groß (${text.length} Zeichen)`);
    }
    return text;
  }

  /** Eine neue Datei anlegen. */
  async create(name: string, deviceId: string, content: string): Promise<{ id: string; modifiedTime: string }> {
    const boundary = `nori-${Math.random().toString(36).slice(2)}-${Date.now().toString(36)}`;
    const metadata = {
      name,
      parents: ["appDataFolder"],
      appProperties: { app: "nori", type: "library-snapshot", syncVersion: "1", deviceId },
    };
    const body = [
      `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(metadata)}`,
      `\r\n--${boundary}\r\nContent-Type: application/json\r\n\r\n${content}`,
      `\r\n--${boundary}--\r\n`,
    ].join("");

    const url = `${UPLOAD_ENDPOINT}?${new URLSearchParams({ uploadType: "multipart", fields: "id,modifiedTime" })}`;
    const response = await this.perform(url, {
      method: "POST",
      headers: { "Content-Type": `multipart/related; boundary=${boundary}` },
      body,
    });
    const parsed = (await response.json()) as { id?: string; modifiedTime?: string };
    if (!parsed.id) throw new DriveError("http", "Antwort ohne Dateikennung", 200);
    return { id: parsed.id, modifiedTime: parsed.modifiedTime ?? "" };
  }

  /**
   * Eine bestehende Datei überschreiben.
   *
   * `files.update` statt jedes Mal `files.create` — sonst entstünde bei jedem
   * Abgleich eine weitere Datei mit demselben Namen, und der Ordner liefe voll.
   */
  async update(id: string, content: string): Promise<string> {
    const url = `${UPLOAD_ENDPOINT}/${encodeURIComponent(id)}?${new URLSearchParams({
      uploadType: "media",
      fields: "id,modifiedTime",
    })}`;
    const response = await this.perform(url, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: content,
    });
    const parsed = (await response.json().catch(() => ({}))) as { modifiedTime?: string };
    return parsed.modifiedTime ?? "";
  }

  /**
   * Senden, mit genau einer Erneuerung nach `401` und begrenztem Backoff.
   *
   * Die eine Erneuerung ist wichtig: ein abgelaufenes Token darf den Abgleich
   * nicht scheitern lassen, aber zwei Fehlschläge hintereinander heißen, dass
   * das Problem nicht das Token ist. Wer es dann weiter versucht, baut eine
   * Endlosschleife gegen Googles Rate Limit.
   */
  private async perform(url: string, init: RequestInit): Promise<Response> {
    let refreshed = false;
    let attempt = 0;

    for (;;) {
      const token = refreshed
        ? await this.authorization.refreshAccessToken()
        : await this.authorization.validAccessToken();

      let response: Response;
      try {
        response = await this.fetchImpl(url, {
          ...init,
          headers: { ...(init.headers as Record<string, string> | undefined), Authorization: `Bearer ${token}` },
        });
      } catch (cause) {
        const error = new DriveError("transport", cause instanceof Error ? cause.message : String(cause));
        if (attempt + 1 >= this.policy.maxAttempts) throw error;
        await this.sleep(retryDelay(this.policy, attempt, this.random()));
        attempt += 1;
        continue;
      }

      if (response.ok) return response;

      switch (response.status) {
        case 401:
          // Genau einmal. Danach ist es kein Tokenproblem mehr.
          if (refreshed) throw new DriveError("notAuthorized", "Nicht mehr autorisiert", 401);
          refreshed = true;
          continue;

        case 403: {
          // Drive benutzt 403 für zweierlei: „darfst du nicht" und „zu
          // schnell". Das eine ist endgültig, das andere nicht — sie
          // auseinanderzuhalten ist der Unterschied zwischen einer
          // Fehlermeldung und einer Endlosschleife.
          const reason = await readReason(response);
          const rateLimited = reason === "rateLimitExceeded" || reason === "userRateLimitExceeded";
          if (rateLimited && attempt + 1 < this.policy.maxAttempts) {
            await this.sleep(retryDelay(this.policy, attempt, this.random()));
            attempt += 1;
            continue;
          }
          throw new DriveError("forbidden", reason || "Zugriff abgelehnt", 403);
        }

        case 404:
          throw new DriveError("notFound", "Datei nicht gefunden", 404);

        case 409:
          throw new DriveError("conflict", "Konflikt beim Schreiben", 409);

        default: {
          const retryable = response.status === 429 || (response.status >= 500 && response.status < 600);
          if (retryable && attempt + 1 < this.policy.maxAttempts) {
            await this.sleep(retryDelay(this.policy, attempt, this.random()));
            attempt += 1;
            continue;
          }
          throw new DriveError("http", await readReason(response), response.status);
        }
      }
    }
  }
}

async function readReason(response: Response): Promise<string> {
  try {
    const body = (await response.json()) as { error?: { errors?: { reason?: string }[]; message?: string } };
    return body.error?.errors?.[0]?.reason ?? body.error?.message ?? "";
  } catch {
    return "";
  }
}
