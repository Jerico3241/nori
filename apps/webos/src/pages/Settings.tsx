// Einstellungen.
//
// Aufgeteilt nach dem, was sie betreffen: Wiedergabe und Sprache gehören zum
// gemeinsamen Nori-Datenmodell und stehen damit auch auf iPhone und Mac;
// Verbindung, TMDB und Bild betreffen nur diesen Fernseher.
//
// Jede Eingabe ist eine Knopfreihe, kein Auswahlfeld — ein Dropdown lässt sich
// mit einer Fernbedienung nur mit Mühe bedienen, weil es den Fokus in eine
// Liste entführt, die man nicht sieht. Die beiden Textfelder (Serveradresse,
// TMDB-Schlüssel) sind die Ausnahme; dort öffnet webOS seine eigene Tastatur.

import { LIBRARY_SCHEMA_VERSION, PLAYBACK_SPEEDS, type CatalogProvider } from "@nori/core";
import { useCallback, useEffect, useState } from "react";

import { restoreFocusSoon } from "../navigation/focusMemory";
import { SpotArea, SpotButton } from "../navigation/Spot";
import { pingServer, type ServerInfo } from "../services/gateway";
import { covers } from "../services/covers";
import { tmdb, type TmdbMode } from "../services/tmdb";
import { useData } from "../state/data";
import { useLibrary } from "../state/library";
import { useSettings } from "../state/settings";

const ROUTE = "settings";
const LANGS: { value: string; label: string }[] = [
  { value: "DE", label: "Deutsch" },
  { value: "GerSub", label: "Deutsche Untertitel" },
  { value: "EN", label: "Englisch" },
];
const HOSTERS = ["VOE", "Vidmoly", "Vidoza", "Lulustream", "Speedfiles", "Filemoon", "Doodstream"];
const TMDB_MODES: { value: TmdbMode; label: string }[] = [
  { value: "server", label: "Über den Nori-Server" },
  { value: "direct", label: "Eigener Schlüssel" },
  { value: "off", label: "Aus" },
];

/** Die Befunde des TMDB-Clients als deutsche Sätze. */
const STATUS_TEXT: Record<string, string> = {
  ok: "antwortet",
  noKey: "kein Schlüssel eingerichtet",
  unauthorized: "Schlüssel abgelehnt (401/403)",
  notFound: "Eintrag dort nicht vorhanden (404)",
  rateLimited: "zu viele Anfragen (429) — Nori wartet",
  unavailable: "nicht erreichbar",
};

export function SettingsPage() {
  const { settings, update, reset } = useSettings();
  const { tmdbRoute } = useData();
  const library = useLibrary();
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
          ? ` · TMDB-Schlüssel vorhanden, ${info.tmdbCacheEntries} Antworten gespeichert`
          : " · ohne TMDB-Schlüssel"),
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
            „Neu &amp; beliebt" und „Für dich" entstehen. Ohne TMDB zeigt Nori die Cover
            und Texte der Quellen. Das ist ein gültiger Zustand, kein Fehler.
          </p>
        </header>

        <Row
          label="Woher die Daten kommen"
          hint="Über den Server liegt der Schlüssel an einer Stelle statt auf jedem Fernseher — und der Zwischenspeicher gilt für alle Geräte."
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
              Der geprüfte Server hat keinen TMDB-Schlüssel. Auf dem Server
              <code> NORI_TMDB_KEY</code> setzen — oder hier „Eigener Schlüssel" wählen.
            </p>
          ) : null}
        </Row>

        {settings.tmdbMode === "direct" ? (
          <Row label="TMDB-Schlüssel" hint="Ein v3-Schlüssel von themoviedb.org. Er bleibt auf diesem Fernseher.">
            <div className="field-row">
              <input
                className="spottable"
                type="password"
                value={tmdbDraft}
                placeholder="leer lassen für Quellcover"
                aria-label="TMDB-Schlüssel"
                onChange={(event) => setTmdbDraft(event.target.value)}
                onBlur={() => update({ tmdbKey: tmdbDraft })}
              />
            </div>
          </Row>
        ) : null}

        <Row label="Zustand" hint="Was Nori bisher zuordnen konnte. Hilft, wenn ein Titel das falsche Bild zeigt.">
          <p className="field-note">
            {diagnostics.available
              ? `Weg: ${tmdbRoute.effective === "server" ? "Nori-Server" : "eigener Schlüssel"}`
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
                  + `${result.progress} Folgen mit Fortschritt. Nichts wurde gelöscht.`,
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
          Bibliotheksschema v{LIBRARY_SCHEMA_VERSION} · {library.state.favorites.length} auf der Merkliste ·{" "}
          {Object.keys(library.state.progress).length} Folgen mit Fortschritt
        </p>
        <p className="field-note">
          Ein Abgleich zwischen Geräten ist nicht eingebaut: die Bibliothek liegt im
          Speicher dieses Fernsehers. Das Format ist dasselbe wie in der
          <code> library.json</code> von iPhone und Mac — ein Stand lässt sich also von
          Hand übernehmen, und beim Einlesen wird zusammengeführt statt ersetzt.
        </p>
      </section>
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
