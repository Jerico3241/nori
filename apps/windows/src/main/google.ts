// Die Google-Anmeldung auf dem Schreibtisch.
//
// ## Ein Knopf, ein Systembrowser, fertig
//
// Für den Nutzer ist es „Mit Google anmelden": der Systembrowser geht auf,
// Google fragt einmal, das Fenster meldet sich zurück. Client-ID, Verifier,
// Redirect-URI und Tokens sind keine Benutzereinstellungen und tauchen in der
// Oberfläche nicht auf.
//
// Technisch ist es der Weg, den Google für installierte Programme vorschreibt:
// **Authorization Code mit PKCE und Loopback-Umleitung** (RFC 8252). Nori
// startet dafür einen HTTP-Dienst auf `127.0.0.1` mit einem vom Betriebssystem
// vergebenen Port, schickt den Browser zu Google und nimmt den Code entgegen,
// wenn Google zurückleitet.
//
// Ausdrücklich **nicht**:
//
// - Ein eingebettetes Anmeldefenster. Google lehnt das seit 2021 ab, und zu
//   Recht: der Nutzer kann dort die Adresszeile nicht prüfen.
// - `urn:ietf:wg:oauth:2.0:oob`. Abgeschaltet.
// - Der Gerätefluss. Der ist für Geräte ohne Browser und Tastatur — ein
//   Schreibtisch hat beides.
//
// ## Wo die Tokens liegen
//
// Verschlüsselt über `safeStorage`, in einer Datei unter `userData`
// (`%APPDATA%\\Nori`). Unter Windows hängt der Schlüssel an DPAPI und damit am
// Benutzerkonto: Wer die Datei kopiert, kann sie auf einem anderen Konto nicht
// lesen. Nie im `localStorage` des Fensters — das ist reiner Text auf der
// Platte, und ein Refresh-Token ist ein Dauerausweis.
//
// Was in kein Protokoll gehört: Tokens, der Code, der Verifier, das Secret.
//
// ## Das Client-Secret
//
// Googles Client-Typ „Desktop" verlangt beim Tauschen ein `client_secret`,
// obwohl RFC 8252 für öffentliche Clients PKCE vorsieht. Google nennt es
// selbst „not treated as a secret" für installierte Programme. Nori nimmt es
// deshalb entgegen, wenn der Build eines mitgibt, und kommt ohne aus, wenn der
// Client ohne eines angelegt wurde. Eingecheckt wird keines.

import { createHash, randomBytes } from "node:crypto";
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import { AddressInfo } from "node:net";
import { readFileSync, writeFileSync, rmSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";

import { app, safeStorage, shell } from "electron";
import { DRIVE_APPDATA_SCOPE, DRIVE_FILE_SCOPE, type GoogleTokens } from "@nori/core";

const AUTH_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth";
const TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token";
const REVOKE_ENDPOINT = "https://oauth2.googleapis.com/revoke";

/** Wie lange der Browser Zeit hat, bevor Nori aufgibt. */
const SIGN_IN_TIMEOUT_MS = 5 * 60_000;

/**
 * Welche Bereiche Nori erbittet.
 *
 * `drive.appdata` ist die primäre Ablage — wie auf iPhone, iPad und Mac: ein
 * versteckter Ordner, den nur Nori sieht und den niemand versehentlich
 * aufräumt. `drive.file` kommt dazu, damit derselbe Stand auch im sichtbaren
 * Ordner „Nori" landet und der Fernseher ihn lesen kann; webOS kommt an
 * `drive.appdata` nicht heran (docs/google-drive-sync.md, Abschnitt 10).
 */
export const DESKTOP_SCOPES = [DRIVE_APPDATA_SCOPE, DRIVE_FILE_SCOPE];

interface StoredTokens extends GoogleTokens {
  clientId: string;
}

export interface GoogleStatus {
  /** Wurde die App mit Zugangsdaten gebaut? Ohne ist die Anmeldung unmöglich. */
  configured: boolean;
  /** Die Client-ID — sie ist öffentlich und darf in der Diagnose stehen. */
  clientId: string;
  /** Liegt ein Token vor? Der Wert selbst verlässt den Hauptprozess nie. */
  signedIn: boolean;
  /** Die erteilten Bereiche, zur Anzeige. */
  scope: string;
  /** Wann das Zugriffstoken abläuft. */
  expiresAt: number | null;
}

function credentials(): { clientId: string; clientSecret: string } {
  return {
    clientId: (process.env.NORI_GOOGLE_DESKTOP_CLIENT_ID ?? __NORI_GOOGLE_CLIENT_ID__ ?? "").trim(),
    clientSecret: (process.env.NORI_GOOGLE_DESKTOP_CLIENT_SECRET ?? __NORI_GOOGLE_CLIENT_SECRET__ ?? "").trim(),
  };
}

function tokenFile(): string {
  return join(app.getPath("userData"), "google-tokens.bin");
}

function readTokens(): StoredTokens | null {
  const file = tokenFile();
  if (!existsSync(file)) return null;
  try {
    const raw = readFileSync(file);
    const json = safeStorage.isEncryptionAvailable()
      ? safeStorage.decryptString(raw)
      : raw.toString("utf8");
    return JSON.parse(json) as StoredTokens;
  } catch {
    // Eine Datei, die sich nicht entschlüsseln lässt, gehört einem anderen
    // Benutzerkonto oder ist beschädigt. Beides heißt: neu anmelden.
    return null;
  }
}

function writeTokens(tokens: StoredTokens | null): void {
  const file = tokenFile();
  if (!tokens) {
    rmSync(file, { force: true });
    return;
  }
  mkdirSync(dirname(file), { recursive: true });
  const json = JSON.stringify(tokens);
  const body = safeStorage.isEncryptionAvailable()
    ? safeStorage.encryptString(json)
    : Buffer.from(json, "utf8");
  writeFileSync(file, body, { mode: 0o600 });
}

function base64url(input: Buffer): string {
  return input.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Die Seite, die der Browser nach der Zustimmung zeigt. */
function closingPage(title: string, message: string): string {
  return `<!doctype html><html lang="de"><head><meta charset="utf-8">
<title>Nori</title><style>
  :root { color-scheme: dark; }
  body { margin:0; height:100vh; display:flex; align-items:center; justify-content:center;
         background:#03070d; color:#f5f8fc;
         font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif; }
  main { text-align:center; padding:2rem; }
  h1 { font-size:1.6rem; margin:0 0 .6rem; }
  p { margin:0; color:#94a3b8; }
</style></head><body><main><h1>${title}</h1><p>${message}</p></main></body></html>`;
}

class SignInFlow {
  private server: Server | null = null;
  private timer: NodeJS.Timeout | null = null;

  /**
   * Anmelden. Läuft, bis der Browser zurückleitet, die Frist abläuft oder
   * jemand abbricht.
   */
  run(): Promise<StoredTokens> {
    const { clientId, clientSecret } = credentials();
    if (!clientId) {
      return Promise.reject(new Error(
        "Diese Fassung wurde ohne Google-Zugangsdaten gebaut. "
        + "Ohne NORI_GOOGLE_DESKTOP_CLIENT_ID gibt es keinen Abgleich.",
      ));
    }

    const verifier = base64url(randomBytes(64));
    const challenge = base64url(createHash("sha256").update(verifier).digest());
    const state = base64url(randomBytes(24));

    return new Promise<StoredTokens>((resolve, reject) => {
      const finish = (error: Error | null, tokens?: StoredTokens) => {
        this.stop();
        if (error) reject(error);
        else resolve(tokens as StoredTokens);
      };

      const onRequest = (req: IncomingMessage, res: ServerResponse) => {
        const url = new URL(req.url ?? "/", "http://127.0.0.1");
        if (url.pathname !== "/nori/oauth") {
          res.writeHead(404).end();
          return;
        }
        const reply = (status: number, body: string) => {
          res.writeHead(status, { "Content-Type": "text/html; charset=utf-8" }).end(body);
        };
        if (url.searchParams.get("state") !== state) {
          reply(400, closingPage("Anmeldung abgelehnt", "Die Antwort passt nicht zur Anfrage."));
          finish(new Error("Die Antwort von Google passt nicht zur Anfrage."));
          return;
        }
        const error = url.searchParams.get("error");
        if (error) {
          reply(200, closingPage("Anmeldung abgebrochen", "Du kannst dieses Fenster schließen."));
          finish(new Error(error === "access_denied" ? "Zugriff nicht erteilt." : `Google meldet: ${error}`));
          return;
        }
        const code = url.searchParams.get("code");
        if (!code) {
          reply(400, closingPage("Anmeldung unvollständig", "Google hat keinen Code geschickt."));
          finish(new Error("Google hat keinen Code geschickt."));
          return;
        }
        reply(200, closingPage("Nori ist verbunden", "Du kannst dieses Fenster schließen."));
        const redirectUri = this.redirectUri();
        void this.exchange(code, verifier, redirectUri, clientId, clientSecret).then(
          (tokens) => finish(null, tokens),
          (cause: Error) => finish(cause),
        );
      };

      const server = createServer(onRequest);
      this.server = server;
      server.on("error", (cause) => finish(cause as Error));
      // Port 0: das Betriebssystem sucht einen freien. Eine feste Nummer wäre
      // eine Wette darauf, dass sie frei ist.
      server.listen(0, "127.0.0.1", () => {
        const params = new URLSearchParams({
          client_id: clientId,
          redirect_uri: this.redirectUri(),
          response_type: "code",
          scope: DESKTOP_SCOPES.join(" "),
          code_challenge: challenge,
          code_challenge_method: "S256",
          state,
          access_type: "offline",
          // Ohne diese Zeile gibt Google beim zweiten Mal kein Refresh-Token
          // mehr — und ohne Refresh-Token ist nach einer Stunde Schluss.
          prompt: "consent",
        });
        void shell.openExternal(`${AUTH_ENDPOINT}?${params.toString()}`);
      });

      this.timer = setTimeout(() => {
        finish(new Error("Die Anmeldung hat zu lange gedauert."));
      }, SIGN_IN_TIMEOUT_MS);
    });
  }

  private redirectUri(): string {
    const address = this.server?.address() as AddressInfo | null;
    return `http://127.0.0.1:${address?.port ?? 0}/nori/oauth`;
  }

  private async exchange(
    code: string,
    verifier: string,
    redirectUri: string,
    clientId: string,
    clientSecret: string,
  ): Promise<StoredTokens> {
    const body = new URLSearchParams({
      code,
      client_id: clientId,
      redirect_uri: redirectUri,
      grant_type: "authorization_code",
      code_verifier: verifier,
    });
    if (clientSecret) body.set("client_secret", clientSecret);
    const res = await fetch(TOKEN_ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body,
    });
    const payload = (await res.json().catch(() => ({}))) as {
      access_token?: string;
      refresh_token?: string;
      expires_in?: number;
      scope?: string;
      error?: string;
      error_description?: string;
    };
    if (!res.ok || !payload.access_token) {
      // Absichtlich ohne den Rumpf: dort steht bei manchen Fehlern der Code.
      throw new Error(payload.error_description ?? payload.error ?? `Google antwortete mit HTTP ${res.status}`);
    }
    return {
      clientId,
      accessToken: payload.access_token,
      refreshToken: payload.refresh_token ?? "",
      expiresAt: Date.now() + (payload.expires_in ?? 3600) * 1000,
      scope: payload.scope ?? DESKTOP_SCOPES.join(" "),
    };
  }

  stop(): void {
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
    this.server?.close();
    this.server = null;
  }
}

let running: SignInFlow | null = null;

export async function signIn(): Promise<GoogleStatus> {
  running?.stop();
  running = new SignInFlow();
  try {
    const tokens = await running.run();
    writeTokens(tokens);
    return status();
  } finally {
    running = null;
  }
}

export function cancelSignIn(): void {
  running?.stop();
  running = null;
}

export function status(): GoogleStatus {
  const { clientId } = credentials();
  const tokens = readTokens();
  return {
    configured: clientId.length > 0,
    clientId,
    signedIn: tokens !== null,
    scope: tokens?.scope ?? "",
    expiresAt: tokens?.expiresAt ?? null,
  };
}

/**
 * Ein gültiges Zugriffstoken — erneuert, wenn es abgelaufen ist.
 *
 * Nur dieser Wert verlässt den Hauptprozess, und er ist eine Stunde gültig.
 * Das Refresh-Token bleibt hier.
 */
export async function accessToken(): Promise<string | null> {
  const tokens = readTokens();
  if (!tokens) return null;
  if (tokens.expiresAt - 60_000 > Date.now()) return tokens.accessToken;
  if (!tokens.refreshToken) return null;

  const { clientSecret } = credentials();
  const body = new URLSearchParams({
    client_id: tokens.clientId,
    refresh_token: tokens.refreshToken,
    grant_type: "refresh_token",
  });
  if (clientSecret) body.set("client_secret", clientSecret);
  const res = await fetch(TOKEN_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  const payload = (await res.json().catch(() => ({}))) as {
    access_token?: string;
    expires_in?: number;
    scope?: string;
    error?: string;
  };
  if (!res.ok || !payload.access_token) {
    // `invalid_grant` heißt: die Berechtigung ist weg. Weiter zu versuchen
    // hilft nicht; die Oberfläche soll nach einer neuen Anmeldung fragen.
    if (payload.error === "invalid_grant") writeTokens(null);
    return null;
  }
  writeTokens({
    ...tokens,
    accessToken: payload.access_token,
    expiresAt: Date.now() + (payload.expires_in ?? 3600) * 1000,
    scope: payload.scope ?? tokens.scope,
  });
  return payload.access_token;
}

/** Nur dieses Gerät trennen. In Drive bleibt alles liegen. */
export function signOut(): GoogleStatus {
  writeTokens(null);
  return status();
}

/**
 * Den Zugriff bei Google zurückziehen.
 *
 * Das gilt für **alle** Geräte an diesem Konto — deshalb steht es in der
 * Oberfläche auch nicht hinter einem unscheinbaren „Abmelden".
 */
export async function revoke(): Promise<GoogleStatus> {
  const tokens = readTokens();
  const value = tokens?.refreshToken || tokens?.accessToken;
  if (value) {
    await fetch(REVOKE_ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ token: value }),
    }).catch(() => undefined);
  }
  writeTokens(null);
  return status();
}
