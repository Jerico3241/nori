// Mehr → Verbindung & TMDB.
//
// Über einen Nori-Server holt der Fernseher Katalog und Stream nicht selbst,
// sondern lässt sie sich weiterreichen — nur so geht die `Referer`-Kopfzeile
// mit, die viele Hoster verlangen. TMDB braucht keine Einrichtung: ein
// Schlüssel ist mitgeliefert, ein eigener hat Vorrang.
//
// Die beiden Textfelder öffnen die Systemtastatur von webOS. Beide sind
// optional.

import type { CatalogProvider } from "@nori/core";
import { useCallback, useEffect, useState } from "react";

import { ChipRow } from "../../components/Chips";
import { Info } from "../More";
import { Screen } from "../../components/Screen";
import { rememberFocus, restoreFocusSoon } from "../../navigation/focusMemory";
import { SpotButton } from "../../navigation/Spot";
import { covers } from "../../services/covers";
import { pingServer, type TransportMode } from "../../services/gateway";
import { tmdb, type TmdbMode } from "../../services/tmdb";
import { tmdbState } from "../../services/tmdbStatus";
import { useData } from "../../state/data";
import { useLibrary } from "../../state/library";
import { useSettings } from "../../state/settings";

const ROUTE = "more-connection";

export function ConnectionPage() {
  const { settings, update } = useSettings();
  const { tmdbRoute } = useData();
  const library = useLibrary();
  const [serverDraft, setServerDraft] = useState(settings.serverUrl);
  const [keyDraft, setKeyDraft] = useState(settings.tmdbKey);
  const [ping, setPing] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [, setTick] = useState(0);

  useEffect(() => restoreFocusSoon(ROUTE, ["connection", "tmdb"], {
    initial: '[data-focus-key="transport-server"]',
    ready: true,
  }), []);

  const testServer = useCallback(async () => {
    setPing("Wird geprüft …");
    try {
      const info = await pingServer(serverDraft);
      update({ serverUrl: serverDraft, transport: "server" });
      setPing(
        `Erreichbar (Version ${info.version})`
        + (info.tmdb
          ? ` · TMDB mit ${info.tmdbKey === "own" ? "eigenem" : "mitgeliefertem"} Schlüssel`
          : " · ohne TMDB"),
      );
    } catch (cause) {
      setPing(`Nicht erreichbar: ${(cause as Error)?.message ?? "keine Verbindung"}`);
    }
  }, [serverDraft, update]);

  const diagnostics = tmdb.diagnostics();
  const state = tmdbState(diagnostics);

  return (
    <Screen route={ROUTE} eyebrow="Mehr" title="Verbindung & TMDB" className="more-sub">
      <div className="settings-grid">
        <section className="setting-card" data-nav-row="" aria-label="Verbindung">
          <h3>Verbindung</h3>
          <p className="card-note">
            Der Nori-Server ist der zuverlässige Weg: nur er darf die Kopfzeile setzen, ohne die
            viele Hoster nichts ausliefern. „Direkt" kommt ohne Einrichtung aus, ist aber ein
            Rückfall.
          </p>
          <ChipRow<TransportMode>
            label="Zugang"
            route={ROUTE}
            area="connection"
            value={settings.transport}
            onChange={(transport) => update({ transport })}
            options={[
              { value: "server", label: "Nori-Server" },
              { value: "direct", label: "Direkt vom Fernseher" },
            ]}
          />
          <label className="field">
            <span>Serveradresse</span>
            <input
              className="spottable text-field"
              data-focus-key="server-url"
              type="url"
              inputMode="url"
              value={serverDraft}
              placeholder="http://192.168.1.20:8730"
              aria-label="Adresse des Nori-Servers"
              onFocus={() => rememberFocus(ROUTE, "connection", "server-url")}
              onChange={(event) => setServerDraft(event.target.value)}
              onBlur={() => update({ serverUrl: serverDraft })}
            />
          </label>
          <div className="card-actions">
            <SpotButton className="hero-btn primary" focusRoute={ROUTE} focusArea="connection" focusKey="server-test" onClick={() => void testServer()}>
              Server prüfen
            </SpotButton>
          </div>
          {ping ? <p className="card-note strong">{ping}</p> : null}
          <h4>Standardquelle</h4>
          <ChipRow<CatalogProvider>
            label="Standardquelle"
            route={ROUTE}
            area="provider"
            value={library.state.provider}
            onChange={(provider) => library.setPreference({ provider })}
            options={[
              { value: "aniworld", label: "AniWorld" },
              { value: "serienstream", label: "Serienstream" },
            ]}
          />
        </section>

        <section className="setting-card" data-nav-row="" aria-label="TMDB">
          <h3>TMDB</h3>
          <Info label="Zustand" hint={state.detail} value={state.label} tone={state.tone} />
          <p className="card-note">
            {diagnostics.available
              ? `Weg: ${tmdbRoute.effective === "server" ? "Nori-Server" : `dieser Fernseher, ${diagnostics.keyOrigin === "own" ? "eigener" : "mitgelieferter"} Schlüssel`}`
              : "Weg: aus"}
            {` · ${diagnostics.titles} Titel zugeordnet`}
            {diagnostics.viaAlternates > 0 ? ` (${diagnostics.viaAlternates} über Alternativtitel)` : ""}
            {` · ${diagnostics.seasons} Staffeln · ${diagnostics.misses} ohne Treffer`}
          </p>
          {tmdbRoute.note ? <p className="card-note">{tmdbRoute.note}</p> : null}
          <ChipRow<TmdbMode>
            label="Woher die Daten kommen"
            route={ROUTE}
            area="tmdb"
            value={settings.tmdbMode}
            onChange={(tmdbMode) => update({ tmdbMode })}
            options={[
              { value: "server", label: "Über den Nori-Server" },
              { value: "direct", label: "Dieser Fernseher" },
              { value: "off", label: "Aus" },
            ]}
          />
          {settings.tmdbMode === "direct" ? (
            <label className="field">
              <span>Eigener TMDB-Schlüssel (optional)</span>
              <input
                className="spottable text-field"
                data-focus-key="tmdb-key"
                type="password"
                value={keyDraft}
                placeholder="leer lassen für den mitgelieferten"
                aria-label="Eigener TMDB-Schlüssel"
                onFocus={() => rememberFocus(ROUTE, "tmdb", "tmdb-key")}
                onChange={(event) => setKeyDraft(event.target.value)}
                onBlur={() => update({ tmdbKey: keyDraft })}
              />
            </label>
          ) : null}
          <div className="card-actions">
            <SpotButton
              className="hero-btn"
              focusRoute={ROUTE}
              focusArea="tmdb"
              focusKey="tmdb-probe"
              onClick={() => {
                setNote("TMDB wird gefragt …");
                void tmdb.probe().then(({ status, ms }) => {
                  setNote(status === "ok" ? `TMDB hat in ${ms} ms geantwortet.` : `TMDB: ${tmdbState(tmdb.diagnostics()).detail}`);
                  setTick((value) => value + 1);
                });
              }}
            >
              Jetzt prüfen
            </SpotButton>
            <SpotButton
              className="hero-btn"
              focusRoute={ROUTE}
              focusArea="tmdb"
              focusKey="tmdb-retry"
              onClick={() => {
                tmdb.retryMisses();
                setNote("Titel ohne Treffer werden beim nächsten Anzeigen erneut gesucht.");
                setTick((value) => value + 1);
              }}
            >
              Fehlende erneut suchen
            </SpotButton>
            <SpotButton
              className="hero-btn"
              focusRoute={ROUTE}
              focusArea="tmdb"
              focusKey="covers-clear"
              onClick={() => {
                covers.clear();
                setNote("Bildspeicher und Zuordnungen geleert.");
                setTick((value) => value + 1);
              }}
            >
              Bildspeicher leeren
            </SpotButton>
          </div>
          {note ? <p className="card-note strong">{note}</p> : null}
        </section>
      </div>
    </Screen>
  );
}
