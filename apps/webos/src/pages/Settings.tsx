// Einstellungen.
//
// Aufgeteilt nach dem, was sie betreffen: Wiedergabe und Sprache gehören zum
// gemeinsamen Nori-Datenmodell und stehen damit auch auf iPhone und Mac;
// Verbindung, TMDB und Bild betreffen nur diesen Fernseher.
//
// Jede Eingabe ist eine Knopfreihe, kein Auswahlfeld — ein Dropdown lässt sich
// mit einer Fernbedienung nur mit Mühe bedienen, weil es den Fokus in eine
// Liste entführt, die man nicht sieht. Die beiden Textfelder (Serveradresse,
// eigener TMDB-Schlüssel) sind die Ausnahme; dort öffnet webOS seine eigene
// Tastatur. Beide sind optional: Nori bringt einen TMDB-Schlüssel mit, und
// ohne Server arbeitet der Fernseher direkt an den Quellen.

import { LIBRARY_SCHEMA_VERSION, PLAYBACK_SPEEDS, type CatalogProvider } from "@nori/core";
import { useCallback, useEffect, useState } from "react";

import { restoreFocusSoon } from "../navigation/focusMemory";
import { SpotArea, SpotButton } from "../navigation/Spot";
import { pingServer, type ServerInfo } from "../services/gateway";
import { covers } from "../services/covers";
import { tmdb, type TmdbMode } from "../services/tmdb";
import { useData } from "../state/data";
import { useLibrary } from "../state/library";
import { syncStatusLabel, useSync } from "../state/sync";
import { useSettings } from "../state/settings";

/** „1 Folge", „2 Folgen". Eine Zahl mit falschem Plural liest sich wie ein Fehler. */
function folgen(count: number): string {
  return count === 1 ? "1 Folge" : `${count} Folgen`;
}

const ROUTE = "settings";
const LANGS: { value: string; label: string }[] = [
  { value: "DE", label: "Deutsch" },
  { value: "GerSub", label: "Deutsche Untertitel" },
  { value: "EN", label: "Englisch" },
];
const HOSTERS = ["VOE", "Vidmoly", "Vidoza", "Lulustream", "Speedfiles", "Filemoon", "Doodstream"];
const TMDB_MODES: { value: TmdbMode; label: string }[] = [
  { value: "server", label: "Über den Nori-Server" },
  { value: "direct", label: "Dieser Fernseher" },
  { value: "off", label: "Aus" },
];

/** Die Befunde des TMDB-Clients als deutsche Sätze. */
const STATUS_TEXT: Record<string, string> = {
  ok: "antwortet",
  noKey: "nicht eingerichtet",
  unauthorized: "Schlüssel abgelehnt (401/403)",
  notFound: "Eintrag dort nicht vorhanden (404)",
  rateLimited: "zu viele Anfragen (429) — Nori wartet",
  unavailable: "nicht erreichbar",
};

export function SettingsPage() {
  const { settings, update, reset } = useSettings();
  const { tmdbRoute } = useData();
  const library = useLibrary();
  const sync = useSync();
  const [serverDraft, setServerDraft] = useState(settings.serverUrl);
  const [ping, setPing] = useState<string | null>(null);
  const [server, setServer] = useState<ServerInfo | null>(null);
  const [tmdbDraft, setTmdbDraft] = useState(settings.tmdbKey);
  const [dataNote, setDataNote] = useState<string | null>(null);
  // Hochgezählt, damit die Diagnosezeile nach dem Leeren neu gelesen wird.
  const [tick, setTick] = useState(0);
  const [clientIdDraft, setClientIdDraft] = useState("");
  const [clientSecretDraft, setClientSecretDraft] = useState("");
  const [credentialsNote, setCredentialsNote] = useState<string | null>(null);

  useEffect(() => restoreFocusSoon(ROUTE, ["playback", "connection"]), []);

  const testServer = useCallback(async () => {
    setPing("wird geprüft …");
    try {
      const info = await pingServer(serverDraft);
      update({ serverUrl: serverDraft, transport: "server" });
      setServer(info);
      setPing(
        `erreichbar (Version ${info.version})`
        + (info.tmdb
          ? ` · TMDB mit ${info.tmdbKey === "own" ? "eigenem" : "mitgeliefertem"} Schlüssel, `
            + `${info.tmdbCacheEntries} Antworten gespeichert`
          : " · ohne TMDB"),
      );
    } catch (cause) {
      setServer(null);
      setPing((cause as Error)?.message ?? "nicht erreichbar");
    }
  }, [serverDraft, update]);

  const diagnostics = tmdb.diagnostics();
  void tick;

  return (
    <div className="page settings">
      <header className="page-head">
        <h1>Einstellungen</h1>
      </header>

      <section className="settings-section">
        <header>
          <h2>Wiedergabe</h2>
          <p>Gilt für alle Nori-Apps, die dieselbe Bibliothek benutzen.</p>
        </header>

        <Row label="Bevorzugte Sprache" hint="Beim Start wird sie automatisch gewählt, wenn die Folge sie anbietet.">
          <SpotArea className="chip-grid" spotlightId="set-lang">
            {LANGS.map((lang) => (
              <SpotButton
                key={lang.value}
                className={library.state.langPref === lang.value ? "selected" : ""}
                aria-pressed={library.state.langPref === lang.value}
                focusRoute={ROUTE}
                focusArea="playback"
                focusKey={`lang-${lang.value}`}
                onClick={() => library.setPreference({ langPref: lang.value })}
              >
                {lang.label}
              </SpotButton>
            ))}
          </SpotArea>
        </Row>

        <Row label="Bevorzugter Hoster" hint="Wird zuerst probiert; scheitert er, geht Nori die Rangfolge durch.">
          <SpotArea className="chip-grid" spotlightId="set-hoster">
            {HOSTERS.map((name) => (
              <SpotButton
                key={name}
                className={library.state.hosterPref.toLowerCase() === name.toLowerCase() ? "selected" : ""}
                aria-pressed={library.state.hosterPref.toLowerCase() === name.toLowerCase()}
                focusRoute={ROUTE}
                focusArea="playback"
                focusKey={`hoster-${name}`}
                onClick={() => library.setPreference({ hosterPref: name })}
              >
                {name}
              </SpotButton>
            ))}
          </SpotArea>
        </Row>

        <Toggle
          label="Nächste Folge automatisch starten"
          hint="Am Ende einer Folge läuft ein Countdown, dann startet die nächste."
          value={library.state.autoplayNext}
          focusKey="autoplay"
          onChange={(value) => library.setPreference({ autoplayNext: value })}
        />

        <Toggle
          label="An der letzten Position fortsetzen"
          hint="Ab acht Sekunden Wiedergabe fragt Nori beim nächsten Start nach."
          value={library.state.resumeEnabled}
          focusKey="resume"
          onChange={(value) => library.setPreference({ resumeEnabled: value })}
        />

        <Row label="Wiedergabegeschwindigkeit">
          <SpotArea className="chip-grid" spotlightId="set-speed">
            {PLAYBACK_SPEEDS.map((speed) => (
              <SpotButton
                key={speed}
                className={library.state.playbackSpeed === speed ? "selected" : ""}
                aria-pressed={library.state.playbackSpeed === speed}
                focusRoute={ROUTE}
                focusArea="playback"
                focusKey={`speed-${speed}`}
                onClick={() => library.setPreference({ playbackSpeed: speed })}
              >
                {speed.toLocaleString("de-DE")}×
              </SpotButton>
            ))}
          </SpotArea>
        </Row>

        <Row label="Sprung mit Links/Rechts">
          <SpotArea className="chip-grid" spotlightId="set-seek">
            {[5, 10, 15, 30].map((step) => (
              <SpotButton
                key={step}
                className={settings.seekStep === step ? "selected" : ""}
                aria-pressed={settings.seekStep === step}
                focusRoute={ROUTE}
                focusArea="playback"
                focusKey={`seek-${step}`}
                onClick={() => update({ seekStep: step })}
              >
                {step} s
              </SpotButton>
            ))}
          </SpotArea>
        </Row>

        <Row label="Bedienung ausblenden nach">
          <SpotArea className="chip-grid" spotlightId="set-chrome">
            {[3, 4, 5, 8].map((seconds) => (
              <SpotButton
                key={seconds}
                className={settings.controlsTimeout === seconds ? "selected" : ""}
                aria-pressed={settings.controlsTimeout === seconds}
                focusRoute={ROUTE}
                focusArea="playback"
                focusKey={`chrome-${seconds}`}
                onClick={() => update({ controlsTimeout: seconds })}
              >
                {seconds} s
              </SpotButton>
            ))}
          </SpotArea>
        </Row>
      </section>

      <section className="settings-section">
        <header>
          <h2>Verbindung</h2>
          <p>
            Über einen Nori-Server holt der Fernseher Katalog und Stream nicht selbst,
            sondern lässt sie sich weiterreichen. Das ist der zuverlässige Weg: nur so
            geht die Kopfzeile mit, die viele Hoster verlangen.
          </p>
        </header>

        <Row label="Zugang">
          <SpotArea className="chip-grid" spotlightId="set-transport">
            <SpotButton
              className={settings.transport === "server" ? "selected" : ""}
              aria-pressed={settings.transport === "server"}
              focusRoute={ROUTE}
              focusArea="connection"
              focusKey="transport-server"
              onClick={() => update({ transport: "server" })}
            >
              Nori-Server
            </SpotButton>
            <SpotButton
              className={settings.transport === "direct" ? "selected" : ""}
              aria-pressed={settings.transport === "direct"}
              focusRoute={ROUTE}
              focusArea="connection"
              focusKey="transport-direct"
              onClick={() => update({ transport: "direct" })}
            >
              Direkt vom Fernseher
            </SpotButton>
          </SpotArea>
          {settings.transport === "direct" ? (
            <p className="field-note">
              Direkt heißt: der Fernseher ruft AniWorld und Serienstream selbst ab. Das
              kommt ohne Einrichtung aus, hängt aber davon ab, dass webOS der App fremde
              Abrufe erlaubt und der Hoster ohne Referer ausliefert — ein Rückfall, kein
              Ersatz.
            </p>
          ) : null}
        </Row>

        <Row label="Serveradresse" hint="Zum Beispiel http://192.168.1.20:8730">
          <div className="field-row">
            <input
              className="spottable"
              type="url"
              inputMode="url"
              value={serverDraft}
              placeholder="http://192.168.1.20:8730"
              aria-label="Adresse des Nori-Servers"
              onChange={(event) => setServerDraft(event.target.value)}
              onBlur={() => update({ serverUrl: serverDraft })}
            />
            <SpotButton
              focusRoute={ROUTE}
              focusArea="connection"
              focusKey="server-test"
              onClick={() => void testServer()}
            >
              Prüfen
            </SpotButton>
          </div>
          {ping ? <p className="field-note">Server: {ping}</p> : null}
        </Row>

        <Row label="Standardquelle">
          <SpotArea className="chip-grid" spotlightId="set-provider">
            {(["aniworld", "serienstream"] as CatalogProvider[]).map((provider) => (
              <SpotButton
                key={provider}
                className={library.state.provider === provider ? "selected" : ""}
                aria-pressed={library.state.provider === provider}
                focusRoute={ROUTE}
                focusArea="connection"
                focusKey={`provider-${provider}`}
                onClick={() => library.setPreference({ provider })}
              >
                {provider === "aniworld" ? "AniWorld" : "Serienstream"}
              </SpotButton>
            ))}
          </SpotArea>
        </Row>
      </section>

      <section className="settings-section">
        <header>
          <h2>TMDB</h2>
          <p>
            TMDB liefert Poster, Hintergrundbilder, Schriftzüge, Beschreibungen,
            Bewertungen, Folgentitel und Folgenbilder — und die Signale, aus denen
            „Neu &amp; beliebt" und „Für dich" entstehen. Ein Schlüssel ist
            mitgeliefert; hier ist nichts einzurichten. Wer einen eigenen einträgt,
            benutzt seinen eigenen — das trennt die Ratenbegrenzung von der
            geteilten Kennung.
          </p>
        </header>

        <Row
          label="Woher die Daten kommen"
          hint="Über den Server gilt der Zwischenspeicher für alle Geräte gemeinsam, und TMDBs Ratenbegrenzung wird einmal statt je Fernseher ausgeschöpft."
        >
          <SpotArea className="chip-grid" spotlightId="set-tmdb-mode">
            {TMDB_MODES.map((mode) => (
              <SpotButton
                key={mode.value}
                className={settings.tmdbMode === mode.value ? "selected" : ""}
                aria-pressed={settings.tmdbMode === mode.value}
                focusRoute={ROUTE}
                focusArea="images"
                focusKey={`tmdb-${mode.value}`}
                onClick={() => update({ tmdbMode: mode.value })}
              >
                {mode.label}
              </SpotButton>
            ))}
          </SpotArea>
          {tmdbRoute.note ? <p className="field-note">{tmdbRoute.note}</p> : null}
          {settings.tmdbMode === "server" && server && !server.tmdb ? (
            <p className="field-note">
              Der geprüfte Server kann kein TMDB. Auf dem Server
              <code> NORI_TMDB_KEY</code> setzen — oder hier „Dieser Fernseher" wählen.
            </p>
          ) : null}
        </Row>

        {settings.tmdbMode === "direct" ? (
          <Row
            label="Eigener TMDB-Schlüssel"
            hint="Optional. Leer heißt: der mitgelieferte Schlüssel. Ein eigener v3-Schlüssel von themoviedb.org bleibt auf diesem Fernseher."
          >
            <div className="field-row">
              <input
                className="spottable"
                type="password"
                value={tmdbDraft}
                placeholder="leer lassen für den mitgelieferten"
                aria-label="Eigener TMDB-Schlüssel"
                onChange={(event) => setTmdbDraft(event.target.value)}
                onBlur={() => update({ tmdbKey: tmdbDraft })}
              />
              {tmdbDraft ? (
                <SpotButton
                  focusRoute={ROUTE}
                  focusArea="images"
                  focusKey="tmdb-key-clear"
                  onClick={() => {
                    setTmdbDraft("");
                    update({ tmdbKey: "" });
                  }}
                >
                  Löschen
                </SpotButton>
              ) : null}
            </div>
          </Row>
        ) : null}

        <Row label="Zustand" hint="Was Nori bisher zuordnen konnte. Hilft, wenn ein Titel das falsche Bild zeigt.">
          <p className="field-note">
            {diagnostics.available
              ? `Weg: ${tmdbRoute.effective === "server"
                ? "Nori-Server"
                : `dieser Fernseher, ${diagnostics.keyOrigin === "own" ? "eigener" : "mitgelieferter"} Schlüssel`}`
              : "Weg: aus"}
            {diagnostics.lastStatus
              ? ` · TMDB ${STATUS_TEXT[diagnostics.lastStatus] ?? diagnostics.lastStatus}`
              : ""}
            {` · ${diagnostics.titles} Titel zugeordnet`}
            {diagnostics.viaAlternates > 0 ? ` (${diagnostics.viaAlternates} über Alternativtitel)` : ""}
            {` · ${diagnostics.seasons} Staffeln · ${diagnostics.misses} ohne Treffer`}
          </p>
          <SpotArea className="filter-row" spotlightId="set-tmdb-cache">
            <SpotButton
              focusRoute={ROUTE}
              focusArea="images"
              focusKey="tmdb-retry"
              onClick={() => {
                tmdb.retryMisses();
                setTick((value) => value + 1);
              }}
            >
              Erneut nach fehlenden suchen
            </SpotButton>
            <SpotButton
              focusRoute={ROUTE}
              focusArea="images"
              focusKey="covers-clear"
              onClick={() => {
                covers.clear();
                setTick((value) => value + 1);
              }}
            >
              Bildspeicher leeren
            </SpotButton>
          </SpotArea>
        </Row>
      </section>

      <section className="settings-section">
        <header>
          <h2>Bild und Leistung</h2>
          <p>Was auf älteren Panels Bilder pro Sekunde kostet, lässt sich hier abschalten.</p>
        </header>

        <Toggle
          label="Weiche Flächen reduzieren"
          hint="Weniger Unschärfe, Schatten und Bewegung. Auf älteren Panels merklich flüssiger."
          value={settings.reduceEffects}
          focusKey="effects"
          onChange={(value) => update({ reduceEffects: value })}
        />

        <Toggle
          label="Diagnoseprotokoll"
          hint="Schreibt Navigation, Auflösung, TMDB und Wiedergabe mit [Nori:webOS] in die Konsole."
          value={settings.debug}
          focusKey="debug"
          onChange={(value) => update({ debug: value })}
        />
      </section>

      <section className="settings-section">
        <header>
          <h2>Synchronisation</h2>
          <p>
            Merkliste, Verlauf und Fortschritt über Google Drive mit iPhone, iPad und Mac
            teilen. Ohne Netz funktioniert Nori vollständig weiter.
          </p>
        </header>

        <Row label="Zustand">
          <span className="field-note">{syncStatusLabel(sync)}</span>
        </Row>

        {!sync.isConfigured ? (
          <>
            {/*
              Hier stand vorher nur ein Knopf, der eine Meldung zeigte. Das war
              eine Sackgasse: wer ein fertiges .ipk installiert, hat keine
              Build-Variable und kam deshalb nie zu einer Anmeldung.
            */}
            <Row
              label="Google-Client-ID"
              hint="Aus einem eigenen Google-Cloud-Projekt, OAuth-Client vom Typ „Fernseher und Geräte mit eingeschränkter Eingabe“. Endet auf .apps.googleusercontent.com"
            >
              <div className="field-row">
                <input
                  className="spottable"
                  type="text"
                  value={clientIdDraft}
                  placeholder="123456-abc.apps.googleusercontent.com"
                  aria-label="Google-Client-ID"
                  onChange={(event) => setClientIdDraft(event.target.value)}
                />
              </div>
            </Row>
            <Row
              label="Client-Secret"
              hint="Googles Fluss für Fernseher verlangt es. Es liegt unverschlüsselt im Speicher dieser App."
            >
              <div className="field-row">
                <input
                  className="spottable"
                  type="password"
                  value={clientSecretDraft}
                  placeholder="GOCSPX-…"
                  aria-label="Google-Client-Secret"
                  onChange={(event) => setClientSecretDraft(event.target.value)}
                />
                <SpotButton
                  focusRoute={ROUTE}
                  focusArea="sync"
                  focusKey="credentials-save"
                  onClick={() => {
                    const problem = sync.saveCredentials(clientIdDraft, clientSecretDraft);
                    setCredentialsNote(problem);
                    if (!problem) {
                      setClientIdDraft("");
                      setClientSecretDraft("");
                    }
                  }}
                >
                  Zugangsdaten sichern
                </SpotButton>
              </div>
            </Row>
            {credentialsNote ? <p className="field-note">{credentialsNote}</p> : null}
          </>
        ) : sync.pending ? <DeviceCodePanel /> : (
          <SpotArea className="filter-row" spotlightId="set-sync">
            {sync.status === "disconnected" ? (
              <SpotButton
                focusRoute={ROUTE}
                focusArea="sync"
                focusKey="connect"
                onClick={() => sync.connect()}
              >
                Mit Google Drive verbinden
              </SpotButton>
            ) : (
              <>
                <SpotButton
                  focusRoute={ROUTE}
                  focusArea="sync"
                  focusKey="sync-now"
                  onClick={() => sync.syncNow()}
                >
                  Jetzt synchronisieren
                </SpotButton>
                <SpotButton
                  focusRoute={ROUTE}
                  focusArea="sync"
                  focusKey="disconnect"
                  onClick={() => sync.disconnect()}
                >
                  Dieses Gerät trennen
                </SpotButton>
                <SpotButton
                  focusRoute={ROUTE}
                  focusArea="sync"
                  focusKey="revoke"
                  onClick={() => {
                    // Betrifft alle Geräte an diesem Konto, nicht nur den
                    // Fernseher. Deshalb wird vorher gefragt.
                    if (window.confirm(
                      "Damit verlieren alle Geräte an diesem Google-Konto den Zugriff — "
                      + "auch iPhone und Mac. Die Bibliothek auf diesem Fernseher bleibt erhalten.",
                    )) sync.revokeAccess();
                  }}
                >
                  Google-Zugriff widerrufen
                </SpotButton>
              </>
            )}
          </SpotArea>
        )}

        {sync.message ? <p className="field-note">{sync.message}</p> : null}
        {sync.lastWarning ? <p className="field-note">{sync.lastWarning}</p> : null}
        {sync.isConfigured ? (
          <>
            {/* Kein Geheimnis: die Client-ID steht in jeder Anmeldeadresse. Sie
                zu sehen ist der einzige Weg zu bemerken, dass beim Einfügen
                etwas verrutscht ist. Das Secret wird nicht angezeigt. */}
            <p className="field-note">Client-ID: {sync.clientId}</p>
            {sync.credentialsFromDevice ? (
              <SpotArea className="filter-row" spotlightId="set-sync-credentials">
                <SpotButton
                  focusRoute={ROUTE}
                  focusArea="sync"
                  focusKey="credentials-clear"
                  onClick={() => sync.clearCredentials()}
                >
                  Zugangsdaten entfernen
                </SpotButton>
              </SpotArea>
            ) : null}
          </>
        ) : (
          <p className="field-note">
            Ohne Zugangsdaten funktioniert die Bibliothek vollständig weiter, nur eben auf
            diesem Fernseher. Die Schritte stehen in docs/google-drive-sync.md.
          </p>
        )}
      </section>

      <section className="settings-section">
        <header>
          <h2>Daten</h2>
          <p>Merkliste, Verlauf und Fortschritt liegen im Format der übrigen Nori-Apps vor.</p>
        </header>
        <SpotArea className="filter-row" spotlightId="set-data">
          <SpotButton
            focusRoute={ROUTE}
            focusArea="data"
            focusKey="export"
            onClick={() => {
              // Kein Download: der Fernseher hat keinen Dateimanager, und
              // webOS blockt einen Download aus einer `file://`-App ohnehin.
              // Der Stand landet in der Konsole, wo ihn der Web-Inspector
              // abholen kann.
              // eslint-disable-next-line no-console
              console.log("[Nori:webOS] library.json\n", library.exportJSON());
              setDataNote("Der Bibliotheksstand steht im Web-Inspector-Protokoll.");
            }}
          >
            Bibliothek ausgeben
          </SpotButton>
          <SpotButton
            focusRoute={ROUTE}
            focusArea="data"
            focusKey="import"
            onClick={() => {
              // `prompt` ist auf webOS die einzige Eingabe, die ohne eigene
              // Tastatur auskommt — und ein eingelesener Stand wird
              // zusammengeführt, nie ersetzt.
              const raw = window.prompt("Bibliothek einlesen (JSON einfügen)");
              if (!raw) return;
              try {
                const result = library.importJSON(raw);
                setDataNote(
                  `Zusammengeführt: ${result.favorites} auf der Merkliste, `
                  + `${folgen(result.progress)} mit Fortschritt. Nichts wurde gelöscht.`,
                );
              } catch (cause) {
                setDataNote(`Nicht lesbar: ${(cause as Error)?.message ?? "ungültiges JSON"}`);
              }
            }}
          >
            Bibliothek einlesen
          </SpotButton>
          <SpotButton
            focusRoute={ROUTE}
            focusArea="data"
            focusKey="clear-history"
            onClick={() => {
              library.clearHistory();
              setDataNote("Verlauf geleert. Fortschritt und Merkliste bleiben.");
            }}
          >
            Verlauf leeren
          </SpotButton>
          <SpotButton
            focusRoute={ROUTE}
            focusArea="data"
            focusKey="reset"
            onClick={() => {
              reset();
              setDataNote("Geräteeinstellungen zurückgesetzt. Die Bibliothek ist unberührt.");
            }}
          >
            Geräteeinstellungen zurücksetzen
          </SpotButton>
        </SpotArea>
        {dataNote ? <p className="field-note">{dataNote}</p> : null}
        <p className="field-note">
          Bibliotheksschema v{LIBRARY_SCHEMA_VERSION} · {library.state.favorites.length} auf der
          Merkliste · {folgen(Object.keys(library.state.progress).length)} mit Fortschritt
        </p>
        <p className="field-note">
          Ohne Google Drive bleibt die Bibliothek im Speicher dieses Fernsehers. Das
          Format ist dasselbe wie in der <code>library.json</code> von iPhone und Mac —
          ein Stand lässt sich also auch von Hand übernehmen, und beim Einlesen wird
          zusammengeführt statt ersetzt.
        </p>
      </section>
    </div>
  );
}

/**
 * Der Gerätefluss, so gross, dass man ihn vom Sofa aus lesen kann.
 *
 * Kein Wartekreisel ohne Erklärung: auf dem Fernseher sieht der Nutzer die
 * Adresse, den Code und wie lange er noch gilt. Was er tun soll, steht dabei —
 * sonst wartet er auf etwas, das ohne ihn nie passiert.
 */
function DeviceCodePanel() {
  const sync = useSync();
  const [remaining, setRemaining] = useState(0);

  const expiresAt = sync.pending?.expiresAt ?? 0;
  useEffect(() => {
    if (!expiresAt) return undefined;
    const tick = () => setRemaining(Math.max(0, Math.round((expiresAt - Date.now()) / 1000)));
    tick();
    const timer = window.setInterval(tick, 1000);
    return () => window.clearInterval(timer);
  }, [expiresAt]);

  if (!sync.pending) return null;
  const minutes = Math.floor(remaining / 60);
  const seconds = String(remaining % 60).padStart(2, "0");

  return (
    <div className="device-code">
      <p className="device-code-lead">
        Öffne diese Adresse auf deinem Smartphone oder Computer und gib den Code ein:
      </p>
      <p className="device-code-url">{sync.pending.verificationUrl}</p>
      <p className="device-code-value">{sync.pending.userCode}</p>
      <p className="device-code-hint">
        {remaining > 0
          ? `Der Code gilt noch ${minutes}:${seconds} Minuten. Nori wartet auf deine Bestätigung …`
          : "Der Code ist abgelaufen. Bitte neu beginnen."}
      </p>
      <SpotArea className="filter-row" spotlightId="set-sync-pending">
        <SpotButton
          focusRoute={ROUTE}
          focusArea="sync"
          focusKey="cancel"
          onClick={() => sync.cancelConnect()}
        >
          Abbrechen
        </SpotButton>
      </SpotArea>
    </div>
  );
}

function Row({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <div className="settings-row">
      <div className="settings-label">
        <strong>{label}</strong>
        {hint ? <small>{hint}</small> : null}
      </div>
      <div className="settings-control">{children}</div>
    </div>
  );
}

function Toggle({ label, hint, value, focusKey, onChange }: {
  label: string;
  hint?: string;
  value: boolean;
  focusKey: string;
  onChange(next: boolean): void;
}) {
  return (
    <Row label={label} hint={hint}>
      <SpotButton
        className={`switch ${value ? "on" : ""}`}
        role="switch"
        aria-checked={value}
        aria-label={label}
        focusRoute={ROUTE}
        focusArea="playback"
        focusKey={focusKey}
        onClick={() => onChange(!value)}
      >
        <i aria-hidden="true" />
        <span>{value ? "An" : "Aus"}</span>
      </SpotButton>
    </Row>
  );
}
