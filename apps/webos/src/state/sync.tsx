// Der Abgleich über Google Drive, von der Oberfläche aus gesehen.
//
// Hier wird zusammengesteckt, was der Kern mitbringt: Zugangsdaten aus der
// Build-Variablen, Tokens im lokalen Speicher, Gerätefluss, Drive-Client,
// Abgleichsablauf. Die Seiten sehen davon nur einen Zustand und vier
// Handlungen.
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
  GoogleAuthError, GoogleDeviceAuthorization, GoogleDriveClient, GoogleDriveSnapshotStore,
  LibrarySyncEngine,
  type DeviceAuthorization, type GoogleTokens, type GoogleTokenStore, type LibrarySyncStatus,
  type SyncBookkeeping,
} from "@nori/core";
import {
  createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode,
} from "react";
import { useLibrary } from "./library";
import { log, warn } from "../services/log";

const TOKEN_KEY = "nori.google.tokens";

/**
 * Wo die Tokens liegen.
 *
 * webOS bietet Web-Apps keinen Schlüsselbund an. Was hier abgelegt wird, liegt
 * im privaten Speicher der App — von anderen Apps nicht lesbar, aber **nicht
 * verschlüsselt**. Das ist eine Einschränkung der Plattform und keine
 * Entscheidung; sie steht so auch in `docs/google-drive-sync.md`, damit
 * niemand `localStorage` für einen sicheren Speicher hält.
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

/**
 * Zugangsdaten aus der Build-Variablen — nicht aus dem Quelltext.
 *
 * Zum `client_secret`: Googles Fluss für Fernseher verlangt ihn, anders als der
 * für native Apps. Das steht im Widerspruch zu der Regel, dass in einer App
 * kein Client-Secret liegen darf, und lässt sich nicht auflösen — ohne den Wert
 * antwortet Google mit `invalid_client`. Er wird deshalb nicht eingecheckt,
 * sondern beim Bauen gesetzt. Warum das vertretbar ist und was es bedeutet,
 * steht in `docs/google-drive-sync.md`.
 */
const configuration = {
  clientId: (import.meta.env.VITE_NORI_GOOGLE_TV_CLIENT_ID as string | undefined) ?? "",
  clientSecret: (import.meta.env.VITE_NORI_GOOGLE_TV_CLIENT_SECRET as string | undefined) ?? "",
};

export interface SyncContextValue {
  isConfigured: boolean;
  status: LibrarySyncStatus;
  lastSuccessfulSync: number | null;
  lastError: string | null;
  lastWarning: string | null;
  /** Läuft der Gerätefluss gerade? Dann steht hier Adresse und Code. */
  pending: DeviceAuthorization | null;
  /** Was während des Verbindens angezeigt wird. */
  message: string | null;
  connect(): void;
  cancelConnect(): void;
  syncNow(): void;
  disconnect(): void;
  revokeAccess(): void;
}

const SyncContext = createContext<SyncContextValue | null>(null);

export function SyncProvider({ children }: { children: ReactNode }) {
  const library = useLibrary();
  const [status, setStatus] = useState<LibrarySyncStatus>("disconnected");
  const [lastSuccessfulSync, setLastSuccessfulSync] = useState<number | null>(null);
  const [lastError, setLastError] = useState<string | null>(null);
  const [lastWarning, setLastWarning] = useState<string | null>(null);
  const [pending, setPending] = useState<DeviceAuthorization | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  // Der Zustand der Bibliothek wechselt bei jeder Änderung; Engine und
  // Autorisierung dürfen das nicht. Deshalb `ref` statt `state`, und der
  // Zugriff auf die Bibliothek läuft über einen mitwandernden Zeiger.
  const libraryRef = useRef(library);
  libraryRef.current = library;

  const authorization = useMemo(() => new GoogleDeviceAuthorization({
    configuration, tokenStore: new LocalTokenStore(),
  }), []);

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

  const abort = useRef<AbortController | null>(null);

  const connect = useCallback(() => {
    if (!authorization.isConfigured) {
      setMessage("Für diese Nori-Fassung sind keine Google-Zugangsdaten hinterlegt.");
      return;
    }
    const controller = new AbortController();
    abort.current = controller;
    engine.setAuthorizing();
    setMessage(null);

    void (async () => {
      try {
        const device = await authorization.requestDeviceCode();
        setPending(device);
        log("app", "Gerätecode angefordert", device.verificationUrl);
        await authorization.pollForTokens(device, { signal: controller.signal });
        setPending(null);
        setMessage(null);
        attach();
      } catch (cause) {
        setPending(null);
        engine.setDisconnected();
        if (cause instanceof GoogleAuthError && cause.kind === "denied" && controller.signal.aborted) {
          // Selbst abgebrochen ist kein Fehler und bekommt keine Meldung.
          setMessage(null);
          return;
        }
        setMessage(cause instanceof Error ? cause.message : String(cause));
      } finally {
        abort.current = null;
      }
    })();
  }, [attach, authorization, engine]);

  const cancelConnect = useCallback(() => {
    abort.current?.abort();
    abort.current = null;
    setPending(null);
    setMessage(null);
    engine.setDisconnected();
  }, [engine]);

  const value = useMemo<SyncContextValue>(() => ({
    isConfigured: authorization.isConfigured,
    status,
    lastSuccessfulSync,
    lastError,
    lastWarning,
    pending,
    message,
    connect,
    cancelConnect,
    syncNow: () => engine.syncNow(),
    disconnect: () => {
      authorization.disconnectDevice();
      engine.disconnect();
      setMessage(null);
    },
    revokeAccess: () => {
      void authorization.revokeAccess();
      engine.disconnect();
      setMessage(null);
    },
  }), [authorization, status, lastSuccessfulSync, lastError, lastWarning, pending, message,
       connect, cancelConnect, engine]);

  return <SyncContext.Provider value={value}>{children}</SyncContext.Provider>;
}

export function useSync(): SyncContextValue {
  const context = useContext(SyncContext);
  if (!context) throw new Error("useSync außerhalb von SyncProvider");
  return context;
}

/** Was in den Einstellungen als Zustand steht. */
export function syncStatusLabel(value: SyncContextValue): string {
  if (!value.isConfigured) return "nicht eingerichtet";
  switch (value.status) {
    case "disconnected": return "nicht verbunden";
    case "authorizing": return "wird verbunden …";
    case "idle": return value.lastSuccessfulSync ? "synchronisiert" : "bereit";
    case "syncing": return "wird abgeglichen …";
    // Kein Alarm: lokal ist alles da, und beim nächsten Netz geht es weiter.
    case "offline": return "offline – wird später abgeglichen";
    case "error": return value.lastError ?? "Fehler";
    case "unsupportedRemoteVersion": return "neuerer Stand in der Cloud – Nori aktualisieren";
    default: return "unbekannt";
  }
}
