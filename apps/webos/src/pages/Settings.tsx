// Einstellungen.
//
// Aufgeteilt nach dem, was sie betreffen: Wiedergabe und Sprache gehören zum
// gemeinsamen Nori-Datenmodell und stehen damit auch auf iPhone und Mac;
// Verbindung und Bild betreffen nur diesen Fernseher.

import { LIBRARY_SCHEMA_VERSION, PLAYBACK_SPEEDS, type CatalogProvider } from "@nori/core";
import { useCallback, useEffect, useState } from "react";

import { restoreFocusSoon } from "../navigation/focusMemory";
import { SpotArea, SpotButton } from "../navigation/Spot";
import { pingServer } from "../services/gateway";
import { covers } from "../services/covers";
import { useLibrary } from "../state/library";
import { syncStatusLabel, useSync } from "../state/sync";
import { useSettings } from "../state/settings";

const ROUTE = "settings";
const LANGS: { value: string; label: string }[] = [
  { value: "DE", label: "Deutsch" },
  { value: "GerSub", label: "Deutsche Untertitel" },
  { value: "EN", label: "Englisch" },
];
const HOSTERS = ["VOE", "Vidmoly", "Vidoza", "Lulustream", "Speedfiles", "Filemoon", "Doodstream"];

export function SettingsPage() {
  const { settings, update, reset } = useSettings();
  const library = useLibrary();
  const sync = useSync();
  const [serverDraft, setServerDraft] = useState(settings.serverUrl);
  const [ping, setPing] = useState<string | null>(null);
  const [tmdbDraft, setTmdbDraft] = useState(settings.tmdbKey);
  const [clientIdDraft, setClientIdDraft] = useState("");
  const [clientSecretDraft, setClientSecretDraft] = useState("");
  const [credentialsNote, setCredentialsNote] = useState<string | null>(null);

  useEffect(() => restoreFocusSoon(ROUTE, ["playback", "connection"]), []);

  const testServer = useCallback(async () => {
    setPing("wird geprüft …");
    try {
      const version = await pingServer(serverDraft);
      update({ serverUrl: serverDraft, transport: "server" });
      setPing(`erreichbar (Version ${version})`);
    } catch (cause) {
      setPing((cause as Error)?.message ?? "nicht erreichbar");
    }
  }, [serverDraft, update]);

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
          <h2>Bild und Leistung</h2>
          <p>
            Ohne TMDB-Schlüssel zeigt Nori die Cover von AniWorld und Serienstream.
            Das ist ein gültiger Zustand, kein Fehler.
          </p>
        </header>

        <Row label="TMDB-Schlüssel" hint="Optional. Liefert Hintergrundbilder für Startseite und Detailseite.">
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
            <SpotButton
              focusRoute={ROUTE}
              focusArea="images"
              focusKey="covers-clear"
              onClick={() => covers.clear()}
            >
              Bildspeicher leeren
            </SpotButton>
          </div>
        </Row>

        <Toggle
          label="Weiche Flächen reduzieren"
          hint="Weniger Unschärfe und Schatten. Auf älteren Panels merklich flüssiger."
          value={settings.reduceEffects}
          focusKey="effects"
          onChange={(value) => update({ reduceEffects: value })}
        />

        <Toggle
          label="Diagnoseprotokoll"
          hint="Schreibt Navigation, Auflösung und Wiedergabe mit [Nori:webOS] in die Konsole."
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
              // Kein Download: der Fernseher hat keinen Dateimanager. Der Stand
              // landet in der Konsole, wo ihn der Web-Inspector abholen kann.
              // eslint-disable-next-line no-console
              console.log("[Nori:webOS] library.json\n", library.exportJSON());
              window.alert("Der Bibliotheksstand steht im Web-Inspector-Protokoll.");
            }}
          >
            Bibliothek ausgeben
          </SpotButton>
          <SpotButton
            focusRoute={ROUTE}
            focusArea="data"
            focusKey="clear-history"
            onClick={() => library.clearHistory()}
          >
            Verlauf leeren
          </SpotButton>
          <SpotButton
            focusRoute={ROUTE}
            focusArea="data"
            focusKey="reset"
            onClick={() => reset()}
          >
            Geräteeinstellungen zurücksetzen
          </SpotButton>
        </SpotArea>
        <p className="field-note">
          Bibliotheksschema v{LIBRARY_SCHEMA_VERSION} · {library.state.favorites.length} auf der
          Merkliste · {Object.keys(library.state.progress).length} Folgen mit Fortschritt
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
