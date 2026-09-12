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
import { useCallback, useEffect, useRef, useState } from "react";

import { QrCode } from "../components/QrCode";
import { useBackHandler } from "../navigation/back";
import { restoreFocusSoon } from "../navigation/focusMemory";
import { focusWithin, SpotArea, SpotButton } from "../navigation/Spot";
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

        <Row label="Google Drive">
          <span className="field-note">{syncStatusLabel(sync)}</span>
        </Row>

        {!sync.isConfigured ? (
          // Kein Eingabefeld. Client-ID und Client-Secret mit einer
          // Fernbedienung über eine Bildschirmtastatur einzugeben war keine
          // Einrichtung, sondern eine Hürde — wer das vor sich hatte, bekam
          // keinen Abgleich. Die Werte kommen aus dem Build; fehlen sie, ist
          // das ein Build-Fehler und steht in der Diagnose.
          <p className="field-note">
            Diese Nori-Fassung wurde ohne Google-Abgleich gebaut. Merkliste, Verlauf und
            Fortschritt funktionieren vollständig weiter — sie bleiben auf diesem Fernseher.
          </p>
        ) : (
          <SpotArea className="filter-row" spotlightId="set-sync">
            {sync.needsReauthorization ? (
              <SpotButton
                className="primary"
                focusRoute={ROUTE}
                focusArea="sync"
                focusKey="reconnect"
                onClick={() => sync.connect()}
              >
                Erneut anmelden
              </SpotButton>
            ) : sync.status === "disconnected" ? (
              <SpotButton
                className="primary"
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
                      "Google-Zugriff widerrufen?\n\n"
                      + "Dadurch kann Nori auf deinen Geräten nicht mehr auf die "
                      + "Google-Drive-Synchronisierung zugreifen. Deine lokale Bibliothek "
                      + "bleibt erhalten.",
                    )) sync.revokeAccess();
                  }}
                >
                  Google-Zugriff widerrufen
                </SpotButton>
              </>
            )}
          </SpotArea>
        )}

        {sync.needsReauthorization ? (
          <p className="field-note">Google Drive muss erneut verbunden werden.</p>
        ) : null}
        {sync.isConfigured && sync.status !== "disconnected" && sync.lastSuccessfulSync ? (
          <p className="field-note">
            Letzte Synchronisierung: {relativeTime(sync.lastSuccessfulSync)}
          </p>
        ) : null}
        {sync.message ? <p className="field-note">{sync.message}</p> : null}
        {sync.lastWarning ? <p className="field-note">{sync.lastWarning}</p> : null}

        {/*
          Die Diagnose hängt am Entwicklerschalter weiter oben und ist sonst
          nicht zu sehen. Sie beantwortet genau eine Frage — „welchen
          Google-Zugang benutzt dieses Paket?" —, und die lässt sich sonst nur
          durch Raten beantworten.

          Das Client-Secret steht hier **nicht**, auch nicht verkürzt. Dass es
          vorhanden ist, reicht als Auskunft.
        */}
        {settings.debug ? (
          <>
            <p className="field-note">
              Client-ID: {sync.diagnostics.clientId || "—"} ·{" "}
              {sync.diagnostics.origin === "build" ? "aus dem Build"
                : sync.diagnostics.origin === "migrated" ? "aus einer früheren Fassung übernommen"
                : "fehlt"} · Client-Secret:{" "}
              {sync.diagnostics.hasSecret ? "vorhanden" : "fehlt"} · Bereich: nur
              drive.appdata
            </p>
            {sync.diagnostics.origin === "migrated" ? (
              <SpotArea className="filter-row" spotlightId="set-sync-credentials">
                <SpotButton
                  focusRoute={ROUTE}
                  focusArea="sync"
                  focusKey="credentials-clear"
                  onClick={() => sync.forgetMigratedCredentials()}
                >
                  Übernommene Zugangsdaten verwerfen
                </SpotButton>
              </SpotArea>
            ) : null}
          </>
        ) : null}
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

      {/* Über allem: solange eine Anmeldung läuft, ist sie das Einzige, was
          zählt. Unten und nicht mitten in der Liste, damit der Dialog die
          ganze Fläche bekommt. */}
      {sync.pending ? <DeviceSignInDialog /> : null}
    </div>
  );
}

/**
 * Die verstrichene Zeit in Worten.
 *
 * „vor wenigen Sekunden" und nicht „vor 3 Sekunden": auf einem Fernseher wird
 * die Zeile nicht jede Sekunde neu gezeichnet, und eine Zahl, die eine Minute
 * lang stehenbleibt, ist falsch.
 */
function relativeTime(stamp: number): string {
  const seconds = Math.max(0, Math.round((Date.now() - stamp) / 1000));
  if (seconds < 45) return "vor wenigen Sekunden";
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return minutes === 1 ? "vor einer Minute" : `vor ${minutes} Minuten`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return hours === 1 ? "vor einer Stunde" : `vor ${hours} Stunden`;
  const days = Math.round(hours / 24);
  return days === 1 ? "gestern" : `vor ${days} Tagen`;
}

/**
 * Der Gerätefluss, so gross, dass man ihn vom Sofa aus lesen kann.
 *
 * Ein eigener Bildschirm und keine Zeile in der Liste. Was hier passiert, ist
 * eine Handlung mit einem zweiten Gerät und dauert eine Minute; sie zwischen
 * „Bevorzugter Hoster" und „Verlauf leeren" abzuwickeln, hiesse sie zu
 * verstecken.
 *
 * Drei Dinge stehen darauf, in dieser Reihenfolge:
 *
 * 1. **Der QR-Code.** Gross, mit hellem Grund und Rand. Er ist der kurze Weg:
 *    Kamera drauf, fertig. Enthält Google eine vollständige Adresse
 *    (`verification_uri_complete` nach RFC 8628), steckt der Code schon darin
 *    und am Telefon ist nichts mehr zu tippen.
 * 2. **Die Adresse und der Code**, für den, der kein Telefon mit Kamera dabei
 *    hat. Beide so gross, dass sie aus drei Metern zu lesen sind.
 * 3. **Wie lange der Code noch gilt.** Ohne das wartet jemand vor einem
 *    Bildschirm, auf dem längst nichts mehr passieren kann.
 *
 * Kein OAuth-Wort, keine Fehlernummer, kein Wartekreisel ohne Erklärung.
 */
function DeviceSignInDialog() {
  const sync = useSync();
  const panel = useRef<HTMLDivElement>(null);

  /*
   * Die Restlaufzeit wird bei jedem Zeichnen gerechnet, nicht gespeichert.
   *
   * Gespeichert begann sie bei null — und für ein Bild stand dann „Der
   * Anmeldecode ist abgelaufen." auf dem Bildschirm, bevor der erste Takt sie
   * richtigstellte. Der Zeitgeber löst nur das Neuzeichnen aus; gerechnet wird
   * aus `expiresAt`, und das ist von Anfang an richtig.
   */
  const expiresAt = sync.pending?.expiresAt ?? 0;
  const [, redraw] = useState(0);
  useEffect(() => {
    if (!expiresAt) return undefined;
    const timer = window.setInterval(() => redraw((n) => n + 1), 1000);
    return () => window.clearInterval(timer);
  }, [expiresAt]);
  const remaining = expiresAt ? Math.max(0, Math.round((expiresAt - Date.now()) / 1000)) : 0;

  // Zurück bricht die Anmeldung ab und schliesst den Dialog — und nicht die
  // Seite darunter.
  useBackHandler(() => {
    sync.cancelConnect();
    return true;
  });

  // Der Fokus muss in den Dialog. Ohne das stünde er weiter auf dem Knopf
  // dahinter: sichtbar wäre der QR-Code, bedient würde die Liste darunter.
  useEffect(() => focusWithin(panel.current), []);

  // Läuft der Code ab, wandert der Fokus auf „Neuen Code erzeugen". Er bliebe
  // sonst auf „Abbrechen" stehen — dem einen Knopf, der hier nicht
  // weiterhilft.
  const expired = sync.expired || (expiresAt > 0 && expiresAt <= Date.now());
  useEffect(() => {
    if (!expired) return undefined;
    return focusWithin(panel.current, '[data-focus-key="device-retry"]', 20, true);
  }, [expired]);

  // Und beim Schliessen zurück in die Abgleich-Reihe. Ein Fokus, der nach dem
  // Schliessen auf `body` liegt, sieht auf dem Fernseher aus wie eine
  // Fernbedienung ohne Batterien.
  useEffect(() => () => { restoreFocusSoon(ROUTE, ["sync"]); }, []);

  if (!sync.pending) return null;

  const minutes = Math.floor(remaining / 60);
  const seconds = String(remaining % 60).padStart(2, "0");
  const shortUrl = sync.pending.verificationUrl.replace(/^https?:\/\//, "");

  return (
    <>
      <div className="device-shade" aria-hidden="true" />
      <SpotArea
        className="device-dialog"
        spotlightId="device-dialog"
        restrict="self-only"
        role="dialog"
        aria-label="Google Drive verbinden"
      >
        <div className="device-panel" ref={panel}>
          <h2>Google Drive verbinden</h2>

          {expired ? (
            <div className="device-expired">
              <p className="device-lead">Der Anmeldecode ist abgelaufen.</p>
              <p className="device-hint">
                Codes gelten nur wenige Minuten. Ein neuer ist sofort da.
              </p>
            </div>
          ) : (
            <div className="device-body">
              <div className="device-qr">
                {/* Genau die Adresse, die Google geliefert hat. Nie eine
                    selbst zusammengesetzte — welchen Parameter Google an
                    google.com/device erwartet, sichert es nirgends zu. */}
                <QrCode
                  value={sync.qrPayload ?? sync.pending.verificationUrl}
                  label={`QR-Code für ${shortUrl}`}
                />
              </div>
              <div className="device-text">
                <p className="device-lead">Scanne den QR-Code mit deinem Smartphone.</p>
                <p className="device-or">Oder öffne am Telefon</p>
                <p className="device-url">{shortUrl}</p>
                <p className="device-or">und gib diesen Code ein</p>
                <p className="device-value">{sync.pending.userCode}</p>
              </div>
            </div>
          )}

          {expired ? null : (
            <p className="device-hint">
              Nori wartet auf deine Anmeldung … Der Code gilt noch {minutes}:{seconds} Minuten.
            </p>
          )}

          <div className="device-actions">
            {expired ? (
              <SpotButton
                className="primary"
                focusKey="device-retry"
                onClick={() => sync.connect()}
              >
                Neuen Code erzeugen
              </SpotButton>
            ) : null}
            <SpotButton focusKey="device-cancel" onClick={() => sync.cancelConnect()}>
              Abbrechen
            </SpotButton>
          </div>
        </div>
      </SpotArea>
    </>
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
