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
  /**
   * Die Adresse, die der Nutzer am Telefon öffnet.
   *
   * Kommt aus `verification_uri` (so heisst das Feld in RFC 8628) oder aus
   * `verification_url` (so heisst es in Googles älterer Beschreibung). Beide
   * werden gelesen, keines wird geraten.
   */
  verificationUrl: string;
  /**
   * Dieselbe Adresse mit dem Code darin — wenn Google eine mitschickt.
   *
   * RFC 8628 nennt das `verification_uri_complete` und sieht es genau für den
   * Fall vor, dass das Gerät einen QR-Code anzeigen kann: der Nutzer scannt,
   * und der Code ist schon eingetragen.
   *
   * Fehlt das Feld, bleibt es **leer**. Eine solche Adresse selbst
   * zusammenzusetzen wäre geraten — welchen Parameternamen Google dort
   * erwartet, sichert es nirgends zu, und ein falscher führt auf eine
   * Fehlerseite statt auf die Zustimmung.
   */
  verificationUrlComplete?: string;
  /** Millisekunden seit 1970, ab wann der Code nicht mehr gilt. */
  expiresAt: number;
  /** Wie oft nachgefragt werden darf. Von Google vorgegeben. */
  intervalMs: number;
}

/**
 * Was in den QR-Code kommt.
 *
 * Die vollständige Adresse, wenn Google eine liefert — dann muss am Telefon
 * niemand mehr tippen. Sonst die schlichte Adresse, und der Code steht
 * daneben auf dem Bildschirm. Nie etwas selbst Gebautes: siehe
 * `verificationUrlComplete`.
 */
export function deviceQrPayload(authorization: DeviceAuthorization): string {
  const complete = authorization.verificationUrlComplete?.trim();
  return complete ? complete : authorization.verificationUrl;
}

export type GoogleAuthErrorKind =
  | "notConfigured"
  /** Der Nutzer hat abgelehnt — oder am Fernseher abgebrochen. */
  | "denied"
  | "expired"
  | "pending"
  | "adminPolicy"
  | "invalidClient"
  /** Google hat den angefragten Bereich für diesen Clienttyp nicht erteilt. */
  | "invalidScope"
  | "noRefreshToken"
  /** Es gibt keine gültige Berechtigung mehr. Die Oberfläche muss neu anmelden. */
  | "notAuthorized"
  | "transport"
  | "server";

/**
 * Fehlercodes von Google auf die Arten oben abbilden.
 *
 * An einer Stelle, weil derselbe Code an drei Endpunkten auftauchen kann und
 * sonst dreimal anders behandelt würde. Was hier nicht steht, bleibt
 * `server` — mit Googles Text, aber ohne Anspruch, ihn zu deuten.
 */
function kindFor(code: string): GoogleAuthErrorKind | null {
  switch (code) {
    case "authorization_pending": return "pending";
    case "access_denied": return "denied";
    case "expired_token":
    case "invalid_grant": return "expired";
    case "admin_policy_enforced": return "adminPolicy";
    case "invalid_client":
    case "unauthorized_client": return "invalidClient";
    case "invalid_scope": return "invalidScope";
    default: return null;
  }
}

/**
 * Eine Zahl aus Googles Antwort, oder der Rückfall.
 *
 * Google schickt `expires_in` und `interval` als Zahl; ein Feld, das fehlt
 * oder Unsinn enthält, würde über `Number()` zu `NaN` — und `NaN` als
 * Ablaufzeit hiesse: der Code ist nie abgelaufen und die Schleife läuft
 * ewig.
 */
function numberOr(value: unknown, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

export class GoogleAuthError extends Error {
  constructor(readonly kind: GoogleAuthErrorKind, message: string) {
    super(message);
    this.name = "GoogleAuthError";
  }
}

/** Woran eine Google-Client-ID zu erkennen ist. */
export const GOOGLE_CLIENT_ID_SUFFIX = ".apps.googleusercontent.com";

/**
 * Sieht der Wert überhaupt nach einer Google-Client-ID aus?
 *
 * Dieselbe Regel wie `GoogleClientIDStore.validationError` im Swift-Kern. Sie
 * ist keine Förmlichkeit: mit einer falschen Client-ID antwortet Google auf
 * die Anfrage nach dem Gerätecode mit `invalid_client`, und auf dem Fernseher
 * sieht das aus wie „der Abgleich ist kaputt".
 */
export function clientIdValidationError(raw: string): string | null {
  const trimmed = raw.trim();
  if (trimmed === "") return "Bitte eine Client-ID eintragen.";
  if (!trimmed.endsWith(GOOGLE_CLIENT_ID_SUFFIX)) {
    return `Eine Google-Client-ID endet auf „${GOOGLE_CLIENT_ID_SUFFIX}".`;
  }
  if (trimmed.length <= GOOGLE_CLIENT_ID_SUFFIX.length) return "Die Client-ID ist unvollständig.";
  return null;
}

/**
 * Das Client-Secret des Fernseher-Clients.
 *
 * Eine feste Form gibt Google nicht zu — die heute ausgegebenen beginnen mit
 * `GOCSPX-`, aber darauf zu bestehen hiesse, eine künftige Schreibweise
 * abzulehnen. Geprüft wird deshalb nur, was sicher falsch ist: leer, oder mit
 * Leerraum mittendrin, wie er beim Einfügen aus einer Zwischenablage entsteht.
 */
export function clientSecretValidationError(raw: string): string | null {
  const trimmed = raw.trim();
  if (trimmed === "") return "Bitte ein Client-Secret eintragen.";
  if (/\s/.test(trimmed)) return "Das Client-Secret enthält Leerzeichen.";
  return null;
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

/**
 * Warten — aber nicht über einen Abbruch hinaus.
 *
 * Ohne das dauerte ein „Abbrechen" bis zu einem ganzen Wartetakt: die
 * Schleife schlief, merkte den Abbruch erst beim Aufwachen und gab bis dahin
 * ihren Platz nicht frei. Auf dem Fernseher sah das so aus: abbrechen,
 * sofort wieder „Verbinden" drücken — und nichts passiert, weil die alte
 * Schleife noch stand.
 *
 * Der Zeitgeber wird nicht abgeräumt, sondern nur nicht mehr abgewartet. Das
 * ist Absicht: `sleep` ist austauschbar (die Tests zählen damit die
 * Wartezeiten), und eine Schnittstelle, die zusätzlich abbrechbar sein muss,
 * wäre eine Zumutung für jeden Aufrufer.
 */
function waitOrAbort(
  sleep: (ms: number) => Promise<void>,
  ms: number,
  signal?: AbortSignal,
): Promise<void> {
  if (!signal) return sleep(ms);
  if (signal.aborted) return Promise.resolve();
  return new Promise<void>((resolve) => {
    let settled = false;
    const finish = () => {
      if (settled) return;
      settled = true;
      signal.removeEventListener("abort", finish);
      resolve();
    };
    signal.addEventListener("abort", finish);
    void sleep(ms).then(finish, finish);
  });
}

export class GoogleDeviceAuthorization {
  private readonly config: GoogleDeviceConfiguration;
  private readonly store: GoogleTokenStore;
  private readonly fetchImpl: typeof fetch;
  private readonly now: () => number;
  /** Läuft schon eine Erneuerung, wird deren Ergebnis geteilt. */
  private refreshing: Promise<GoogleTokens> | null = null;
  /** Läuft schon eine Gerätecode-Schleife? Eine zweite wäre doppeltes Fragen. */
  private polling = false;

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
    }, { allowErrorBody: true });

    if (typeof body.error === "string") {
      // Schon hier sauber unterscheiden. `invalid_client` heisst „falsch
      // gebaut", nicht „probier es nochmal" — und die Oberfläche soll das eine
      // nicht wie das andere anzeigen.
      throw new GoogleAuthError(
        kindFor(body.error) ?? "server",
        String(body.error_description ?? body.error),
      );
    }
    if (typeof body.device_code !== "string" || typeof body.user_code !== "string") {
      throw new GoogleAuthError("server", "Antwort ohne Gerätecode.");
    }

    // `verification_uri` ist der Name aus RFC 8628, `verification_url` der aus
    // Googles älterer Beschreibung. Google schickt beide; gelesen werden beide,
    // und keines wird ersetzt, wenn eines fehlt.
    const verificationUrl = typeof body.verification_uri === "string"
      ? body.verification_uri
      : typeof body.verification_url === "string"
        ? body.verification_url
        : null;
    if (!verificationUrl) throw new GoogleAuthError("server", "Antwort ohne Anmeldeadresse.");

    return {
      deviceCode: body.device_code,
      userCode: body.user_code,
      verificationUrl,
      verificationUrlComplete: typeof body.verification_uri_complete === "string"
        ? body.verification_uri_complete
        : undefined,
      expiresAt: this.now() + numberOr(body.expires_in, 1800) * 1000,
      // Googles Vorgabe wird eingehalten, nicht unterboten: wer schneller
      // fragt, bekommt `slow_down` und wartet danach länger als vorher.
      intervalMs: numberOr(body.interval, 5) * 1000,
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
    // Zwei Schleifen auf denselben Gerätecode wären doppelt so viele Anfragen
    // wie erlaubt — und Google antwortete beiden mit `slow_down`. Passieren
    // kann das leicht: ein zweiter Druck auf „Verbinden", während die erste
    // Schleife schon läuft.
    if (this.polling) {
      throw new GoogleAuthError("pending", "Es läuft schon eine Anmeldung.");
    }
    this.polling = true;
    try {
      return await this.poll(authorization, options);
    } finally {
      this.polling = false;
    }
  }

  private async poll(
    authorization: DeviceAuthorization,
    options: { signal?: AbortSignal; sleep?: (ms: number) => Promise<void> },
  ): Promise<GoogleTokens> {
    const sleep = options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
    let interval = authorization.intervalMs;

    for (;;) {
      if (options.signal?.aborted) throw new GoogleAuthError("denied", "Abgebrochen.");
      if (this.now() >= authorization.expiresAt) {
        throw new GoogleAuthError("expired", "Der Code ist abgelaufen. Bitte neu beginnen.");
      }
      await waitOrAbort(sleep, interval, options.signal);
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

      const code = typeof body.error === "string" ? body.error : "";
      if (code === "authorization_pending") continue;   // Der Nutzer tippt noch.
      if (code === "slow_down") {
        // RFC 8628, Abschnitt 3.5: das Intervall wird erhöht, nicht
        // beibehalten. Fünf Sekunden mehr — und falls Google selbst eine
        // längere Wartezeit nennt, gilt die.
        interval = Math.max(interval + 5_000, numberOr(body.interval, 0) * 1000);
        continue;
      }

      switch (kindFor(code)) {
        case "denied":
          throw new GoogleAuthError("denied", "Der Zugriff wurde abgelehnt.");
        case "expired":
          throw new GoogleAuthError("expired", "Der Code ist abgelaufen. Bitte neu beginnen.");
        case "adminPolicy":
          throw new GoogleAuthError("adminPolicy", "Die Google-Organisation erlaubt diesen Zugriff nicht.");
        case "invalidClient":
          throw new GoogleAuthError("invalidClient", "Die hinterlegten Google-Zugangsdaten stimmen nicht.");
        case "invalidScope":
          throw new GoogleAuthError("invalidScope", "Google hat den benötigten Drive-Zugriff nicht erteilt.");
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
      // Ohne Bereiche in der Antwort gelten die bisherigen.
      fresh.scope = fresh.scope ?? tokens?.scope;
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
