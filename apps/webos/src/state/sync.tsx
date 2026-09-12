// Der Abgleich über Google Drive, von der Oberfläche aus gesehen.
//
// Hier wird zusammengesteckt, was der Kern mitbringt: Zugangsdaten aus dem
// Build, Tokens im lokalen Speicher, Gerätefluss, Drive-Client,
// Abgleichsablauf. Die Seiten sehen davon einen Zustand und eine Handvoll
// Handlungen — und keine OAuth-Begriffe.
//
// ## Keine Eingabe am Fernseher
//
// Frühere Fassungen liessen Client-ID und Client-Secret in den Einstellungen
// eintragen. Mit einer Fernbedienung über eine Bildschirmtastatur, ein Wert
// davon 40 Zeichen lang. Das war keine Einrichtung, das war eine Hürde: wer
// Nori auf dem Fernseher installiert, hat am Ende keinen Abgleich.
//
// Die Werte kommen jetzt aus dem Build (`VITE_NORI_GOOGLE_TV_CLIENT_ID` und
// `VITE_NORI_GOOGLE_TV_CLIENT_SECRET`, am besten über eine nicht eingecheckte
// `apps/webos/.env.local`). Was eine ältere Fassung im Gerät hinterlassen hat,
// wird weiter gelesen — sonst verlöre eine bestehende Verbindung beim Update
// ihren Sinn, ohne Grund und ohne Meldung.
//
// ## Zwei Dinge, die nicht dasselbe sind
//
// „Dieses Gerät trennen" hört auf abzugleichen: die Bibliothek bleibt
// vollständig, die Dateien in Drive bleiben liegen, die anderen Geräte gleichen
// weiter ab. „Google-Zugriff widerrufen" zieht die Berechtigung für *alle*
// Geräte an diesem Konto zurück. Das Zweite hinter einem unscheinbaren
// „Abmelden" zu verstecken, wäre die Art Fehler, die jemand erst bemerkt, wenn
// das iPhone nicht mehr mitkommt.

import {
  deviceQrPayload,
  GoogleAuthError, GoogleDeviceAuthorization, GoogleDriveClient, GoogleDriveSnapshotStore,
  LibrarySyncEngine,
  type DeviceAuthorization, type GoogleDeviceConfiguration, type GoogleTokens,
  type GoogleTokenStore, type LibrarySyncStatus, type SyncBookkeeping,
} from "@nori/core";
import {
  createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode,
} from "react";
import { useLibrary } from "./library";
import { warn } from "../services/log";

const TOKEN_KEY = "nori.google.tokens";
const CLIENT_ID_KEY = "nori.google.clientId";
const CLIENT_SECRET_KEY = "nori.google.clientSecret";

/**
 * Wo die Tokens liegen.
 *
 * webOS bietet Web-Apps keinen Schlüsselbund an. Was hier abgelegt wird, liegt
 * im privaten Speicher der App — von anderen Apps nicht lesbar, aber **nicht
 * verschlüsselt**. Das ist eine Einschränkung der Plattform und keine
 * Entscheidung; sie steht so auch in `docs/google-drive-sync.md`, damit
 * niemand `localStorage` für einen sicheren Speicher hält.
 *
 * Was hier **nicht** passiert: protokollieren. Kein `log()` mit einem Token
 * als Argument, auch nicht im Fehlerfall — der Web-Inspector eines Fernsehers
 * ist über das Netz erreichbar.
 */
class LocalTokenStore implements GoogleTokenStore {
  read(): GoogleTokens | null {
    try {
      const raw = localStorage.getItem(TOKEN_KEY);
      return raw ? (JSON.parse(raw) as GoogleTokens) : null;
    } catch {
      return null;
    }
  }

  write(tokens: GoogleTokens | null): void {
    try {
      if (tokens) localStorage.setItem(TOKEN_KEY, JSON.stringify(tokens));
      else localStorage.removeItem(TOKEN_KEY);
    } catch (cause) {
      warn("app", "Google-Tokens nicht speicherbar", cause);
    }
  }
}

/**
 * Die Merkposten der Engine.
 *
 * Ausdrücklich nicht in der Bibliothek: die Drive-Dateikennung gehört zu einem
 * Google-Konto und nicht zu den Daten. Stünde sie dort, wanderte sie beim
 * nächsten Abgleich auf alle anderen Geräte — und die schrieben dann in *diese*
 * Datei.
 */
const bookkeeping: SyncBookkeeping = {
  get: (key) => {
    try { return localStorage.getItem(key); } catch { return null; }
  },
  set: (key, value) => {
    try {
      if (value === null) localStorage.removeItem(key); else localStorage.setItem(key, value);
    } catch { /* Ein voller Speicher darf den Abgleich nicht abbrechen. */ }
  },
};

function readItem(key: string): string {
  try {
    return localStorage.getItem(key)?.trim() ?? "";
  } catch {
    return "";
  }
}

function forgetItem(key: string): void {
  try {
    localStorage.removeItem(key);
  } catch { /* Nicht löschbar heisst: es bleibt bei der alten Quelle. */ }
}

/** Woher die benutzten Zugangsdaten stammen. Für die Diagnose, nie für die Logik. */
export type CredentialOrigin = "build" | "migrated" | "missing";

export interface CredentialDiagnostics {
  /** Kein Geheimnis: die Client-ID steht in jeder Anmeldeadresse. */
  clientId: string;
  /** Ob ein Secret vorliegt — **nie** welches. */
  hasSecret: boolean;
  origin: CredentialOrigin;
}

/**
 * Die Zugangsdaten: aus dem Build, sonst die einer früheren Fassung.
 *
 * Diese Reihenfolge ist Absicht und nicht andersherum: wer schon verbunden
 * ist, hat seine Tokens zu den im Gerät eingetragenen Werten bekommen. Wären
 * die ab jetzt ohne Wirkung, wäre die Verbindung nach dem Update weg. Sie
 * haben deshalb weiter Vorrang — und wenn sie mit denen aus dem Build
 * übereinstimmen, wird die Kopie im Gerät gleich aufgeräumt.
 *
 * Zum `client_secret`: Googles Fluss für Fernseher verlangt ihn, anders als
 * der für native Apps. Das lässt sich nicht auflösen — ohne den Wert antwortet
 * Google mit `invalid_client`. Er wird nicht eingecheckt; warum das vertretbar
 * ist und warum er trotzdem nicht wirklich geheim bleibt, steht in
 * `docs/google-drive-sync.md`.
 */
function readCredentials(): GoogleDeviceConfiguration & { origin: CredentialOrigin } {
  const build = {
    clientId: (import.meta.env.VITE_NORI_GOOGLE_TV_CLIENT_ID as string | undefined)?.trim() ?? "",
    clientSecret: (import.meta.env.VITE_NORI_GOOGLE_TV_CLIENT_SECRET as string | undefined)?.trim() ?? "",
  };
  const stored = { clientId: readItem(CLIENT_ID_KEY), clientSecret: readItem(CLIENT_SECRET_KEY) };

  if (stored.clientId && stored.clientSecret) {
    if (stored.clientId === build.clientId && stored.clientSecret === build.clientSecret) {
      // Dieselben Werte, nur an zwei Orten. Einer reicht, und der Speicher des
      // Fernsehers ist der schlechtere davon.
      forgetItem(CLIENT_ID_KEY);
      forgetItem(CLIENT_SECRET_KEY);
      return { ...build, origin: "build" };
    }
    return { ...stored, origin: "migrated" };
  }
  if (build.clientId && build.clientSecret) return { ...build, origin: "build" };
  return { clientId: build.clientId, clientSecret: build.clientSecret, origin: "missing" };
}

export interface SyncContextValue {
  /** Bringt dieser Build einen Google-Abgleich mit? */
  isConfigured: boolean;
  status: LibrarySyncStatus;
  /** Gilt die Berechtigung nicht mehr? Dann führt genau ein Knopf weiter. */
  needsReauthorization: boolean;
  lastSuccessfulSync: number | null;
  lastError: string | null;
  lastWarning: string | null;
  /** Läuft der Gerätefluss gerade? Dann steht hier Adresse, Code und Ablauf. */
  pending: DeviceAuthorization | null;
  /** Die Adresse für den QR-Code — oder leer, solange nichts läuft. */
  qrPayload: string | null;
  /** Ist der angezeigte Code abgelaufen? Dann hilft nur ein neuer. */
  expired: boolean;
  /** Was während des Verbindens in verständlichen Worten anzuzeigen ist. */
  message: string | null;
  /** Nur für den Diagnosebereich. Enthält **kein** Secret. */
  diagnostics: CredentialDiagnostics;
  connect(): void;
  cancelConnect(): void;
  /** Nur im Diagnosebereich: die Werte einer früheren Fassung verwerfen. */
  forgetMigratedCredentials(): void;
  syncNow(): void;
  disconnect(): void;
  revokeAccess(): void;
}

const SyncContext = createContext<SyncContextValue | null>(null);

/**
 * Googles Fehler in Sätzen, die am Fernseher etwas bedeuten.
 *
 * Kein `invalid_client` auf dem Bildschirm. Wer vom Sofa aus zusieht, kann mit
 * einem OAuth-Code nichts anfangen — und die Hälfte dieser Fälle ist ohnehin
 * kein Fehler des Nutzers.
 */
function messageFor(cause: unknown): string {
  if (!(cause instanceof GoogleAuthError)) {
    return "Die Verbindung zu Google ist fehlgeschlagen. Bitte später erneut versuchen.";
  }
  switch (cause.kind) {
    case "notConfigured":
      return "Diese Nori-Fassung wurde ohne Google-Abgleich gebaut.";
    case "expired":
      return "Der Anmeldecode ist abgelaufen.";
    case "denied":
      return "Die Anmeldung wurde abgebrochen.";
    case "adminPolicy":
      return "Die Einstellungen dieses Google-Kontos erlauben den Zugriff nicht.";
    case "invalidClient":
    case "invalidScope":
      return "Der Google-Zugang dieser Nori-Fassung stimmt nicht. Siehe Diagnose.";
    case "noRefreshToken":
      return "Google hat keine dauerhafte Berechtigung erteilt. Bitte erneut anmelden.";
    case "notAuthorized":
      return "Google Drive muss erneut verbunden werden.";
    case "transport":
      return "Google ist nicht erreichbar. Bitte die Netzverbindung prüfen.";
    default:
      return "Die Verbindung zu Google ist fehlgeschlagen. Bitte später erneut versuchen.";
  }
}

export function SyncProvider({ children }: { children: ReactNode }) {
  const library = useLibrary();
  const [status, setStatus] = useState<LibrarySyncStatus>("disconnected");
  const [lastSuccessfulSync, setLastSuccessfulSync] = useState<number | null>(null);
  const [lastError, setLastError] = useState<string | null>(null);
  const [lastWarning, setLastWarning] = useState<string | null>(null);
  const [pending, setPending] = useState<DeviceAuthorization | null>(null);
  const [expired, setExpired] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  // Die laufende Abfrage beim Gerätefluss, damit sie sich abbrechen lässt.
  const abort = useRef<AbortController | null>(null);

  // Der Zustand der Bibliothek wechselt bei jeder Änderung; Engine und
  // Autorisierung dürfen das nicht. Deshalb `ref` statt `state`, und der
  // Zugriff auf die Bibliothek läuft über einen mitwandernden Zeiger.
  const libraryRef = useRef(library);
  libraryRef.current = library;

  // Die Zugangsdaten können sich im Betrieb noch ändern — nicht mehr durch
  // eine Eingabe, sondern durch das Aufräumen der Werte einer früheren
  // Fassung. Ein einmal gebautes Autorisierungsobjekt wäre danach auf die
  // alten geeicht.
  const [credentials, setCredentials] = useState(readCredentials);

  const authorization = useMemo(() => new GoogleDeviceAuthorization({
    configuration: { clientId: credentials.clientId, clientSecret: credentials.clientSecret },
    tokenStore: new LocalTokenStore(),
  }), [credentials]);

  const engine = useMemo(() => new LibrarySyncEngine({
    host: {
      snapshot: () => libraryRef.current.snapshot(),
      applyMerged: (merged) => libraryRef.current.applyMerged(merged),
      get deviceId() { return libraryRef.current.state.deviceId; },
    },
    bookkeeping,
    onChange: (current) => {
      setStatus(current.status);
      setLastSuccessfulSync(current.lastSuccessfulSync);
      setLastError(current.lastError);
      setLastWarning(current.lastWarning);
    },
  }), []);

  const attach = useCallback(() => {
    const client = new GoogleDriveClient({ authorization });
    // `connect` gleicht sofort ab: wer sich gerade angemeldet hat, soll seine
    // Merkliste sehen und nicht erst einen Knopf suchen.
    engine.connect(new GoogleDriveSnapshotStore(client), authorization.accountFingerprint);
    engine.startPolling();
  }, [authorization, engine]);

  // Eine bestehende Verbindung nach dem Start wieder aufnehmen. Hier wird
  // nichts gefragt und kein Code angezeigt: liegen Tokens vor, geht es weiter.
  useEffect(() => {
    if (!authorization.isConnected) return undefined;
    attach();
    return () => engine.stopPolling();
  }, [attach, authorization, engine]);

  // Änderungen an der Bibliothek melden. Der Zeitplan der Engine entscheidet,
  // wann daraus ein Upload wird.
  useEffect(() => {
    library.setChangeListener((duringPlayback) => engine.noteChange(duringPlayback));
    return () => library.setChangeListener(null);
  }, [library, engine]);

  // Eine unterbrochene Anmeldung darf nicht weiterlaufen, wenn die App
  // weggeht: die Schleife fragte sonst gegen einen Code, den niemand mehr
  // sieht.
  useEffect(() => () => abort.current?.abort(), []);

  const connect = useCallback(() => {
    if (!authorization.isConfigured) {
      setMessage("Diese Nori-Fassung wurde ohne Google-Abgleich gebaut.");
      return;
    }
    // Ein zweiter Druck auf „Verbinden", während die erste Schleife läuft,
    // wäre doppeltes Fragen — und Google antwortete beiden mit `slow_down`.
    if (abort.current) return;

    const controller = new AbortController();
    abort.current = controller;
    engine.setAuthorizing();
    setMessage(null);
    setExpired(false);

    void (async () => {
      try {
        const device = await authorization.requestDeviceCode();
        if (controller.signal.aborted) return;
        setPending(device);
        // Ausdrücklich **ohne** Code und ohne Adresse: der `user_code` ist für
        // die Dauer seiner Gültigkeit ein Zugang, und der Web-Inspector eines
        // Fernsehers ist über das Netz erreichbar.
        await authorization.pollForTokens(device, { signal: controller.signal });
        setPending(null);
        setMessage(null);
        attach();
      } catch (cause) {
        engine.setDisconnected();
        if (cause instanceof GoogleAuthError && cause.kind === "denied" && controller.signal.aborted) {
          // Selbst abgebrochen ist kein Fehler und bekommt keine Meldung.
          setPending(null);
          setMessage(null);
          return;
        }
        if (cause instanceof GoogleAuthError && cause.kind === "expired") {
          // Der Dialog bleibt stehen und bietet einen neuen Code an. Ihn
          // wegzuräumen hiesse, den Nutzer ohne Erklärung zurückzuschicken.
          setExpired(true);
          setMessage(null);
          return;
        }
        setPending(null);
        setMessage(messageFor(cause));
      } finally {
        if (abort.current === controller) abort.current = null;
      }
    })();
  }, [attach, authorization, engine]);

  const cancelConnect = useCallback(() => {
    abort.current?.abort();
    abort.current = null;
    setPending(null);
    setExpired(false);
    setMessage(null);
    engine.setDisconnected();
  }, [engine]);

  const forgetMigratedCredentials = useCallback(() => {
    abort.current?.abort();
    abort.current = null;
    forgetItem(CLIENT_ID_KEY);
    forgetItem(CLIENT_SECRET_KEY);
    // Die Tokens gehören zu genau diesen Zugangsdaten und wären danach wertlos.
    authorization.disconnectDevice();
    engine.disconnect();
    setPending(null);
    setExpired(false);
    setMessage(null);
    setCredentials(readCredentials());
  }, [authorization, engine]);

  const value = useMemo<SyncContextValue>(() => ({
    isConfigured: authorization.isConfigured,
    status,
    needsReauthorization: status === "needsReauthorization",
    lastSuccessfulSync,
    lastError,
    lastWarning,
    pending,
    qrPayload: pending ? deviceQrPayload(pending) : null,
    expired,
    message,
    diagnostics: {
      clientId: credentials.clientId,
      hasSecret: credentials.clientSecret !== "",
      origin: credentials.origin,
    },
    connect,
    cancelConnect,
    forgetMigratedCredentials,
    syncNow: () => engine.syncNow(),
    disconnect: () => {
      authorization.disconnectDevice();
      engine.disconnect();
      setMessage(null);
    },
    revokeAccess: () => {
      // `revokeAccess` räumt die Tokens selbst weg und schluckt einen
      // fehlgeschlagenen Widerruf; ohne `void` wäre das eine unbeachtete
      // Zusage.
      void authorization.revokeAccess();
      engine.disconnect();
      setMessage(null);
    },
  }), [authorization, status, lastSuccessfulSync, lastError, lastWarning, pending, expired,
       message, credentials, connect, cancelConnect, forgetMigratedCredentials, engine]);

  return <SyncContext.Provider value={value}>{children}</SyncContext.Provider>;
}

export function useSync(): SyncContextValue {
  const context = useContext(SyncContext);
  if (!context) throw new Error("useSync außerhalb von SyncProvider");
  return context;
}

/** Was in den Einstellungen als Zustand steht. */
export function syncStatusLabel(value: SyncContextValue): string {
  if (!value.isConfigured) return "nicht verfügbar";
  switch (value.status) {
    case "disconnected": return "nicht verbunden";
    case "authorizing": return "wird verbunden …";
    case "idle": return value.lastSuccessfulSync ? "verbunden" : "bereit";
    case "syncing": return "wird abgeglichen …";
    // Kein Alarm: lokal ist alles da, und beim nächsten Netz geht es weiter.
    case "offline": return "offline – wird später abgeglichen";
    case "needsReauthorization": return "Anmeldung nötig";
    case "error": return value.lastError ?? "Fehler";
    case "unsupportedRemoteVersion": return "neuerer Stand in der Cloud – Nori aktualisieren";
    default: return "unbekannt";
  }
}
