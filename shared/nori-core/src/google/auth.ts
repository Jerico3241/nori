// Google-Autorisierung für Geräte mit Fernbedienung.
//
// Auf einem Fernseher gibt es keinen Browser, in dem sich jemand anmelden
// könnte, und keine Tastatur, auf der er ein Passwort tippen möchte. Google
// sieht dafür den Fluss für Fernseher und Geräte mit eingeschränkter Eingabe
// vor: das Gerät holt einen kurzen Code, der Nutzer gibt ihn am Telefon ein,
// und das Gerät fragt in Ruhe nach, ob es so weit ist.
//
// ## Das Client-Secret
//
// Dieser Fluss verlangt beim Abholen des Tokens ein `client_secret` — anders
// als der Fluss für native Apps, bei dem Google es ausdrücklich als optional
// führt. Das steht im Widerspruch zu der Regel, dass in einer App kein
// Client-Secret liegen darf, und lässt sich nicht auflösen: ohne den Wert
// antwortet Google mit `invalid_client`.
//
// Deshalb, in dieser Reihenfolge:
//
// 1. Der Wert wird **nicht** eingecheckt. Er kommt wie die Client-ID aus einer
//    Build-Variablen und liegt nur in der gebauten `.ipk`.
// 2. Er ist für diesen Clienttyp kein vertrauliches Geheimnis im eigentlichen
//    Sinn — Google gibt ihn für Geräte-Clients aus, die ihn naturgemäß nicht
//    schützen können, und der Fluss hängt seine Sicherheit stattdessen an die
//    Zustimmung am zweiten Gerät.
// 3. Er berechtigt zu nichts ohne die ausdrückliche Zustimmung eines Nutzers,
//    und er öffnet nur `drive.appdata`.
//
// Ausführlich steht das in `docs/google-drive-sync.md`. Wer es überliest und
// den Wert versehentlich einträgt, soll wenigstens wissen, was er tut.

import { DRIVE_APPDATA_SCOPE } from "./drive.js";

const DEVICE_CODE_ENDPOINT = "https://oauth2.googleapis.com/device/code";
const TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token";
const REVOCATION_ENDPOINT = "https://oauth2.googleapis.com/revoke";

export interface GoogleTokens {
  accessToken: string;
  /** Nur beim ersten Mal dabei. Wer ihn beim Erneuern überschreibt, verliert ihn. */
  refreshToken?: string;
  /** Millisekunden seit 1970. */
  expiresAt: number;
  scope?: string;
}

/**
 * Wohin die Tokens gelegt werden.
 *
 * webOS bietet Web-Apps keinen Schlüsselbund an. Was hier abgelegt wird, liegt
 * im privaten Speicher der App — von anderen Apps nicht lesbar, aber auch
 * nicht verschlüsselt. Das ist eine Einschränkung der Plattform und keine
 * Entscheidung; sie ist in `docs/google-drive-sync.md` festgehalten, damit
 * niemand `localStorage` für einen sicheren Speicher hält.
 */
export interface GoogleTokenStore {
  read(): GoogleTokens | null;
  write(tokens: GoogleTokens | null): void;
}

export interface GoogleDeviceConfiguration {
  clientId: string;
  /** Siehe den Kommentarblock oben. Leer heißt: nicht eingerichtet. */
  clientSecret: string;
  scopes?: string[];
}

/** Was dem Nutzer auf dem Fernseher angezeigt wird. */
export interface DeviceAuthorization {
  deviceCode: string;
  /** Der kurze Code zum Abtippen, etwa „ABCD-EFGH". */
  userCode: string;
  /** Die Adresse, die der Nutzer am Telefon öffnet. */
  verificationUrl: string;
  /** Millisekunden seit 1970, ab wann der Code nicht mehr gilt. */
  expiresAt: number;
  /** Wie oft nachgefragt werden darf. Von Google vorgegeben. */
  intervalMs: number;
}

export type GoogleAuthErrorKind =
  | "notConfigured"
  | "denied"
  | "expired"
  | "pending"
  | "adminPolicy"
  | "invalidClient"
  | "noRefreshToken"
  | "notAuthorized"
  | "transport"
  | "server";

export class GoogleAuthError extends Error {
  constructor(readonly kind: GoogleAuthErrorKind, message: string) {
    super(message);
    this.name = "GoogleAuthError";
  }
}

export function tokensAreValid(tokens: GoogleTokens | null, now: number, leewayMs = 60_000): boolean {
  // Eine Minute Vorlauf: ein Token, das in fünf Sekunden abläuft, ist
  // praktisch abgelaufen — die Anfrage ist noch unterwegs, wenn es so weit ist.
  return Boolean(tokens?.accessToken) && (tokens as GoogleTokens).expiresAt - leewayMs > now;
}

export interface GoogleAuthorizationOptions {
  configuration: GoogleDeviceConfiguration;
  tokenStore: GoogleTokenStore;
  fetchImpl?: typeof fetch;
  now?: () => number;
}

/** Ein Speicher im Arbeitsspeicher — für Tests und als Rückfall. */
export class MemoryTokenStore implements GoogleTokenStore {
  private tokens: GoogleTokens | null;
  constructor(tokens: GoogleTokens | null = null) { this.tokens = tokens; }
  read(): GoogleTokens | null { return this.tokens; }
  write(tokens: GoogleTokens | null): void { this.tokens = tokens; }
}

export class GoogleDeviceAuthorization {
  private readonly config: GoogleDeviceConfiguration;
  private readonly store: GoogleTokenStore;
  private readonly fetchImpl: typeof fetch;
  private readonly now: () => number;
  /** Läuft schon eine Erneuerung, wird deren Ergebnis geteilt. */
  private refreshing: Promise<GoogleTokens> | null = null;

  constructor(options: GoogleAuthorizationOptions) {
    this.config = options.configuration;
    this.store = options.tokenStore;
    this.fetchImpl = options.fetchImpl ?? ((...args) => fetch(...args));
    this.now = options.now ?? (() => Date.now());
  }

  get isConfigured(): boolean {
    return Boolean(this.config.clientId) && Boolean(this.config.clientSecret);
  }

  get isConnected(): boolean {
    return Boolean(this.store.read()?.refreshToken);
  }

  /**
   * Womit sich ein Kontowechsel erkennen lässt, ohne nach dem Konto zu fragen.
   *
   * Nori fordert weder `email` noch `profile` an. Genommen wird deshalb ein
   * einfacher Fingerabdruck des Auffrischungstokens; er verrät ihn nicht und
   * unterscheidet zwei Konten zuverlässig.
   */
  get accountFingerprint(): string | null {
    const refresh = this.store.read()?.refreshToken;
    if (!refresh) return null;
    let hash = 0x811c9dc5;
    for (let i = 0; i < refresh.length; i += 1) {
      hash ^= refresh.charCodeAt(i);
      hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    return hash.toString(16).padStart(8, "0");
  }

  // MARK: - Gerätecode

  /** Schritt 1: einen Code holen, den der Nutzer am Telefon eingibt. */
  async requestDeviceCode(): Promise<DeviceAuthorization> {
    if (!this.isConfigured) {
      throw new GoogleAuthError("notConfigured", "Keine Google-Zugangsdaten hinterlegt.");
    }
    const body = await this.post(DEVICE_CODE_ENDPOINT, {
      client_id: this.config.clientId,
      scope: (this.config.scopes ?? [DRIVE_APPDATA_SCOPE]).join(" "),
    });
    if (typeof body.device_code !== "string" || typeof body.user_code !== "string") {
      throw new GoogleAuthError("server", "Antwort ohne Gerätecode.");
    }
    return {
      deviceCode: body.device_code,
      userCode: body.user_code,
      verificationUrl: (body.verification_url ?? body.verification_uri ?? "https://www.google.com/device") as string,
      expiresAt: this.now() + Number(body.expires_in ?? 1800) * 1000,
      // Googles Vorgabe wird eingehalten, nicht unterboten: wer schneller
      // fragt, bekommt `slow_down` und wartet danach länger als vorher.
      intervalMs: Number(body.interval ?? 5) * 1000,
    };
  }

  /**
   * Schritt 2: nachfragen, bis der Nutzer bestätigt hat.
   *
   * Ein Durchlauf, kein Dauerlauf: die Schleife endet, wenn der Code abläuft,
   * wenn der Nutzer ablehnt oder wenn abgebrochen wird.
   */
  async pollForTokens(
    authorization: DeviceAuthorization,
    options: { signal?: AbortSignal; sleep?: (ms: number) => Promise<void> } = {},
  ): Promise<GoogleTokens> {
    const sleep = options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
    let interval = authorization.intervalMs;

    for (;;) {
      if (options.signal?.aborted) throw new GoogleAuthError("denied", "Abgebrochen.");
      if (this.now() >= authorization.expiresAt) {
        throw new GoogleAuthError("expired", "Der Code ist abgelaufen. Bitte neu beginnen.");
      }
      await sleep(interval);
      if (options.signal?.aborted) throw new GoogleAuthError("denied", "Abgebrochen.");
      // Auch nach dem Warten: in der Zwischenzeit kann der Code abgelaufen
      // sein, und dann ist die Anfrage vergebens.
      if (this.now() >= authorization.expiresAt) {
        throw new GoogleAuthError("expired", "Der Code ist abgelaufen. Bitte neu beginnen.");
      }

      const body = await this.post(TOKEN_ENDPOINT, {
        client_id: this.config.clientId,
        client_secret: this.config.clientSecret,
        device_code: authorization.deviceCode,
        grant_type: "urn:ietf:params:oauth:grant-type:device_code",
      }, { allowErrorBody: true });

      if (typeof body.access_token === "string") {
        const tokens = this.tokensFrom(body);
        if (!tokens.refreshToken) {
          // Ohne Auffrischungstoken hielte die Verbindung eine Stunde und wäre
          // danach ohne Zutun weg. Das ist kein Erfolg.
          throw new GoogleAuthError("noRefreshToken", "Google hat keine dauerhafte Berechtigung erteilt.");
        }
        this.store.write(tokens);
        return tokens;
      }

      switch (body.error) {
        case "authorization_pending":
          // Der Normalfall, solange der Nutzer noch tippt.
          break;
        case "slow_down":
          // Googles Bitte, langsamer zu machen. Fünf Sekunden mehr, wie im
          // Protokoll vorgesehen.
          interval += 5_000;
          break;
        case "access_denied":
          throw new GoogleAuthError("denied", "Der Zugriff wurde abgelehnt.");
        case "expired_token":
        case "invalid_grant":
          throw new GoogleAuthError("expired", "Der Code ist abgelaufen. Bitte neu beginnen.");
        case "admin_policy_enforced":
          throw new GoogleAuthError("adminPolicy", "Die Google-Organisation erlaubt diesen Zugriff nicht.");
        case "invalid_client":
          throw new GoogleAuthError("invalidClient", "Die hinterlegten Google-Zugangsdaten stimmen nicht.");
        default:
          throw new GoogleAuthError("server", String(body.error_description ?? body.error ?? "Unbekannter Fehler"));
      }
    }
  }

  // MARK: - Token

  async validAccessToken(): Promise<string> {
    const tokens = this.store.read();
    if (!tokens) throw new GoogleAuthError("notAuthorized", "Nicht mit Google verbunden.");
    if (tokensAreValid(tokens, this.now())) return tokens.accessToken;
    return this.refreshAccessToken();
  }

  async refreshAccessToken(): Promise<string> {
    // Zwei gleichzeitige Erneuerungen desselben Tokens beantwortet Google mit
    // `invalid_grant` — und danach ist die Verbindung weg.
    if (this.refreshing) return (await this.refreshing).accessToken;

    const tokens = this.store.read();
    const refreshToken = tokens?.refreshToken;
    if (!refreshToken) throw new GoogleAuthError("notAuthorized", "Nicht mit Google verbunden.");

    this.refreshing = (async () => {
      const body = await this.post(TOKEN_ENDPOINT, {
        client_id: this.config.clientId,
        client_secret: this.config.clientSecret,
        refresh_token: refreshToken,
        grant_type: "refresh_token",
      }, { allowErrorBody: true });

      if (typeof body.access_token !== "string") {
        if (body.error === "invalid_grant") {
          // Der Auffrischungstoken gilt nicht mehr: widerrufen, Passwort
          // geändert, zu lange nicht benutzt. Er ist wertlos und wird
          // weggeräumt, damit die Oberfläche „neu verbinden" anbieten kann.
          this.store.write(null);
          throw new GoogleAuthError("notAuthorized", "Die Verbindung zu Google ist abgelaufen.");
        }
        throw new GoogleAuthError("server", String(body.error_description ?? body.error ?? "Erneuern fehlgeschlagen"));
      }

      const fresh = this.tokensFrom(body);
      // Beim Erneuern schickt Google den Auffrischungstoken nicht erneut mit.
      fresh.refreshToken = fresh.refreshToken ?? refreshToken;
      this.store.write(fresh);
      return fresh;
    })();

    try {
      return (await this.refreshing).accessToken;
    } finally {
      this.refreshing = null;
    }
  }

  /** Dieses Gerät trennen: Tokens weg, sonst nichts. */
  disconnectDevice(): void {
    this.store.write(null);
  }

  /**
   * Den Zugriff bei Google vollständig zurückziehen.
   *
   * Betrifft **alle** Geräte an diesem Konto, nicht nur den Fernseher.
   */
  async revokeAccess(): Promise<void> {
    const tokens = this.store.read();
    this.store.write(null);
    if (!tokens) return;
    try {
      await this.post(REVOCATION_ENDPOINT, { token: tokens.refreshToken ?? tokens.accessToken }, { allowErrorBody: true });
    } catch {
      // Der Widerruf ist dem Nutzer wichtig, nicht das Ergebnis dieser
      // Anfrage: die Tokens sind lokal ohnehin schon weg.
    }
  }

  // MARK: - Innereien

  private tokensFrom(body: Record<string, unknown>): GoogleTokens {
    return {
      accessToken: String(body.access_token),
      refreshToken: typeof body.refresh_token === "string" ? body.refresh_token : undefined,
      expiresAt: this.now() + Number(body.expires_in ?? 3600) * 1000,
      scope: typeof body.scope === "string" ? body.scope : undefined,
    };
  }

  private async post(
    url: string,
    fields: Record<string, string>,
    options: { allowErrorBody?: boolean } = {},
  ): Promise<Record<string, unknown>> {
    let response: Response;
    try {
      response = await this.fetchImpl(url, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams(fields).toString(),
      });
    } catch (cause) {
      throw new GoogleAuthError("transport", cause instanceof Error ? cause.message : String(cause));
    }

    let body: Record<string, unknown> = {};
    try {
      body = (await response.json()) as Record<string, unknown>;
    } catch {
      body = {};
    }
    if (!response.ok && !options.allowErrorBody) {
      throw new GoogleAuthError("server", String(body.error_description ?? body.error ?? `HTTP ${response.status}`));
    }
    return body;
  }
}
