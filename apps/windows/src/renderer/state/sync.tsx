// Der Abgleich über Google Drive, vom Fenster aus gesehen.
//
// ## Zwei Ablagen, wie auf dem Mac
//
//     drive.appdata   die primäre Ablage. Ein versteckter Ordner, den nur Nori
//                     sieht, den niemand versehentlich aufräumt und der beim
//                     Deinstallieren mitgeht. iPhone, iPad und Mac legen dort
//                     ab — damit ist der Schreibtisch in derselben Runde.
//
//     drive.file      der sichtbare Spiegel im Ordner „Nori". Nur dann, wenn
//                     „Mit Fernseher teilen" eingeschaltet ist. Der Fernseher
//                     kommt an `drive.appdata` nicht heran (Googles Gerätefluss
//                     lehnt den Bereich reproduzierbar ab, siehe
//                     docs/google-drive-sync.md, Abschnitt 10) — der Spiegel
//                     ist die Brücke dorthin.
//
// Eine Dateikennung gehört genau zu einer Ablage: `nori.sync.*` für den
// `appDataFolder`, `nori.sync.tvMirror.*` für den Spiegel. Sie wandert nie in
// die andere.
//
// ## Was hier nicht steht
//
// Kein OAuth. Die Anmeldung läuft im Hauptprozess (`src/main/google.ts`), weil
// dort der Systembrowser und die verschlüsselte Ablage sind. Das Fenster
// bekommt ein Zugriffstoken, das eine Stunde gilt — und nie ein Refresh-Token.
//
// ## Zwei Dinge, die nicht dasselbe sind
//
// „Dieses Gerät trennen" hört auf abzugleichen: die Bibliothek bleibt, die
// Dateien in Drive bleiben, andere Geräte gleichen weiter ab. „Google-Zugriff
// widerrufen" zieht die Berechtigung für **alle** Geräte zurück. Das Zweite
// hinter einem unscheinbaren „Abmelden" zu verstecken, wäre die Art Fehler,
// die jemand erst bemerkt, wenn das iPhone nicht mehr mitkommt.

import { log, useLibrary, useSettings, warn } from "@nori/app";
import {
  GoogleDriveClient, GoogleDriveSnapshotStore, LibrarySyncEngine,
  type DriveAuthorization, type LibrarySyncStatus, type SyncBookkeeping,
} from "@nori/core";
import {
  createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode,
} from "react";

import { bridge, type GoogleStatus } from "../bridge";

const MIRROR_PREFIX = "nori.sync.tvMirror";

export interface SyncView {
  /** Wurde die App überhaupt mit Zugangsdaten gebaut? */
  isConfigured: boolean;
  status: LibrarySyncStatus;
  signedIn: boolean;
  clientId: string;
  scope: string;
  lastSuccessfulSync: number | null;
  lastError: string | null;
  /** Läuft gerade eine Anmeldung im Browser? */
  signingIn: boolean;
  /** Spiegelt dieses Gerät zusätzlich in den sichtbaren Ordner „Nori"? */
  shareWithTv: boolean;
  setShareWithTv(value: boolean): void;
  connect(): void;
  syncNow(): void;
  disconnect(): void;
  revoke(): void;
}

const SyncContext = createContext<SyncView | null>(null);

/** Merkposten im `localStorage` — Dateikennungen, Konto, letzter Upload. */
function bookkeeping(): SyncBookkeeping {
  return {
    get: (key) => {
      try {
        return localStorage.getItem(key);
      } catch {
        return null;
      }
    },
    set: (key, value) => {
      try {
        if (value === null) localStorage.removeItem(key);
        else localStorage.setItem(key, value);
      } catch {
        /* voller Speicher darf den Abgleich nicht abbrechen */
      }
    },
  };
}

export function SyncProvider({ children }: { children: ReactNode }) {
  const library = useLibrary();
  const [status, setStatus] = useState<LibrarySyncStatus>("disconnected");
  const [google, setGoogle] = useState<GoogleStatus>({
    configured: false, clientId: "", signedIn: false, scope: "", expiresAt: null,
  });
  const [signingIn, setSigningIn] = useState(false);
  const [lastError, setLastError] = useState<string | null>(null);
  const [lastSuccessfulSync, setLastSuccessfulSync] = useState<number | null>(null);
  // Der Schalter gehört in die Einstellungen, nicht in einen Ansichtszustand:
  // er muss einen Neustart überleben.
  const { settings, update } = useSettings();
  const shareWithTv = settings.shareWithTv;
  const setShareWithTv = useCallback(
    (value: boolean) => update({ shareWithTv: value }),
    [update],
  );

  const libraryRef = useRef(library);
  libraryRef.current = library;

  /**
   * Das Zugriffstoken kommt aus dem Hauptprozess.
   *
   * `refreshAccessToken` und `validAccessToken` sind hier dasselbe: Der
   * Hauptprozess weiß selbst, ob das Token noch gilt, und erneuert es
   * gegebenenfalls. Das Fenster hat kein Refresh-Token, mit dem es etwas
   * anderes tun könnte.
   */
  const authorization = useMemo<DriveAuthorization>(() => {
    const fetchToken = async () => {
      const token = await bridge()?.google.accessToken();
      if (!token) throw new Error("Nicht angemeldet");
      return token;
    };
    return { validAccessToken: fetchToken, refreshAccessToken: fetchToken };
  }, []);

  const host = useMemo(() => ({
    snapshot: () => libraryRef.current.snapshot(),
    applyMerged: (merged: Parameters<typeof library.applyMerged>[0]) =>
      libraryRef.current.applyMerged(merged),
    get deviceId() { return libraryRef.current.state.deviceId; },
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }), []);

  const onEngineChange = useCallback((engine: LibrarySyncEngine) => {
    setStatus(engine.status);
    setLastError(engine.lastError);
    setLastSuccessfulSync(engine.lastSuccessfulSync);
  }, []);

  /** Die primäre Ablage: der `appDataFolder`. */
  const engine = useMemo(() => new LibrarySyncEngine({
    host,
    bookkeeping: bookkeeping(),
    onChange: onEngineChange,
  }), [host, onEngineChange]);

  /**
   * Der sichtbare Spiegel für den Fernseher.
   *
   * Eigene Engine mit eigenem Merkposten-Präfix — und **nicht** dieselbe mit
   * anderer Ablage: die Dateikennung des `appDataFolder` zeigt auf eine Datei,
   * die es im Spiegel nicht gibt.
   */
  const mirror = useMemo(() => new LibrarySyncEngine({
    host,
    bookkeeping: bookkeeping(),
    keyPrefix: MIRROR_PREFIX,
    onChange: () => undefined,
  }), [host]);

  // Den Anmeldezustand vom Hauptprozess holen.
  const refreshGoogle = useCallback(async () => {
    const api = bridge();
    if (!api) return null;
    const next = await api.google.status();
    setGoogle(next);
    return next;
  }, []);

  useEffect(() => {
    void refreshGoogle();
  }, [refreshGoogle]);

  // Verbinden, sobald ein Token vorliegt.
  useEffect(() => {
    if (!google.signedIn) {
      engine.setDisconnected();
      mirror.disconnect();
      return;
    }
    const store = new GoogleDriveSnapshotStore(new GoogleDriveClient({ authorization, space: "appData" }));
    engine.connect(store, google.clientId);
    engine.startPolling();
    log("app", "Abgleich verbunden", "appData");
  }, [google.signedIn, google.clientId, authorization, engine, mirror]);

  useEffect(() => {
    if (!google.signedIn || !shareWithTv) {
      mirror.disconnect();
      return;
    }
    const store = new GoogleDriveSnapshotStore(new GoogleDriveClient({ authorization, space: "tvMirror" }));
    mirror.connect(store, google.clientId);
    log("app", "Abgleich verbunden", "tvMirror");
  }, [google.signedIn, google.clientId, shareWithTv, authorization, mirror]);

  // Jede Änderung an der Bibliothek meldet sich bei beiden Engines.
  useEffect(() => {
    library.setChangeListener((duringPlayback) => {
      engine.noteChange(duringPlayback);
      mirror.noteChange(duringPlayback);
    });
    return () => library.setChangeListener(null);
  }, [library, engine, mirror]);

  const connect = useCallback(() => {
    const api = bridge();
    if (!api) return;
    setSigningIn(true);
    setLastError(null);
    engine.setAuthorizing();
    void api.google.signIn().then((reply) => {
      setSigningIn(false);
      if (reply.ok && reply.value) {
        setGoogle(reply.value);
        return;
      }
      setLastError(reply.message ?? "Anmeldung fehlgeschlagen");
      engine.setDisconnected();
      warn("app", "Google-Anmeldung fehlgeschlagen", reply.message);
    });
  }, [engine]);

  const disconnect = useCallback(() => {
    const api = bridge();
    engine.disconnect();
    mirror.disconnect();
    void api?.google.signOut().then(setGoogle);
  }, [engine, mirror]);

  const revoke = useCallback(() => {
    const api = bridge();
    engine.disconnect();
    mirror.disconnect();
    void api?.google.revoke().then(setGoogle);
  }, [engine, mirror]);

  const value = useMemo<SyncView>(() => ({
    isConfigured: google.configured,
    status,
    signedIn: google.signedIn,
    clientId: google.clientId,
    scope: google.scope,
    lastSuccessfulSync,
    lastError,
    signingIn,
    shareWithTv,
    setShareWithTv,
    connect,
    syncNow: () => {
      engine.syncNow();
      if (shareWithTv) mirror.syncNow();
    },
    disconnect,
    revoke,
  }), [
    google, status, lastSuccessfulSync, lastError, signingIn, shareWithTv, setShareWithTv,
    connect, disconnect, revoke, engine, mirror,
  ]);

  return <SyncContext.Provider value={value}>{children}</SyncContext.Provider>;
}

export function useSync(): SyncView {
  const value = useContext(SyncContext);
  if (!value) throw new Error("useSync außerhalb von SyncProvider");
  return value;
}

export function syncStatusLabel(view: SyncView): string {
  if (!view.isConfigured) return "nicht verfügbar";
  if (view.signingIn) return "Anmeldung läuft …";
  switch (view.status) {
    case "disconnected": return "nicht verbunden";
    case "authorizing": return "wird verbunden …";
    case "syncing": return "gleicht ab …";
    case "idle": return view.lastSuccessfulSync ? "aktuell" : "verbunden";
    case "error": return "Fehler";
    default: return String(view.status);
  }
}
