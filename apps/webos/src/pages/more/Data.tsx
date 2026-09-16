// Mehr → Daten.
//
// Merkliste, Verlauf und Fortschritt liegen im Format der übrigen Nori-Apps
// vor. Ohne Google Drive bleiben sie im Speicher dieses Fernsehers; ein Stand
// lässt sich von Hand übernehmen, und beim Einlesen wird zusammengeführt statt
// ersetzt.
//
// Kein Download: der Fernseher hat keinen Dateimanager, und webOS blockt einen
// Download aus einer `file://`-App. Die Ausgabe landet im Protokoll, wo der
// Web-Inspector sie abholt.

import { LIBRARY_SCHEMA_VERSION } from "@nori/core";
import { useEffect, useState } from "react";

import { Dialog } from "../../components/Overlay";
import { Screen } from "../../components/Screen";
import { restoreFocusSoon } from "../../navigation/focusMemory";
import { SpotButton } from "../../navigation/Spot";
import { useLibrary } from "../../state/library";
import { useSettings } from "../../state/settings";
import { Info, Row } from "../More";

const ROUTE = "more-data";

function folgen(count: number): string {
  return count === 1 ? "1 Folge" : `${count} Folgen`;
}

type Confirm = "history" | "progress" | "reset" | null;

export function DataPage() {
  const library = useLibrary();
  const { reset } = useSettings();
  const [note, setNote] = useState<string | null>(null);
  const [confirm, setConfirm] = useState<Confirm>(null);

  useEffect(() => restoreFocusSoon(ROUTE, ["data"], { initial: '[data-focus-key="export"]', ready: true }), []);

  const run = () => {
    if (confirm === "history") {
      library.clearHistory();
      setNote("Verlauf der geöffneten Titel geleert. Fortschritt und Merkliste bleiben.");
    } else if (confirm === "progress") {
      library.clearProgress();
      setNote("Fortschritt aller Folgen gelöscht. Die Merkliste bleibt.");
    } else if (confirm === "reset") {
      reset();
      setNote("Geräteeinstellungen zurückgesetzt. Die Bibliothek ist unberührt.");
    }
    setConfirm(null);
  };

  return (
    <Screen route={ROUTE} eyebrow="Mehr" title="Daten" className="more-sub">
      <div className="settings-grid">
        <section className="setting-card" data-nav-row="" aria-label="Bibliothek">
          <h3>Bibliothek</h3>
          <Info label="Schema" value={`v${LIBRARY_SCHEMA_VERSION}`} tone="idle" />
          <Info label="Merkliste" value={`${library.state.favorites.length} Titel`} tone="idle" />
          <Info label="Fortschritt" value={folgen(Object.keys(library.state.progress).length)} tone="idle" />
          <Row
            route={ROUTE}
            area="data"
            id="export"
            label="Bibliothek ausgeben"
            hint="In das Protokoll, abholbar über den Web-Inspector"
            value=""
            chevron
            onClick={() => {
              // eslint-disable-next-line no-console
              console.log("[Nori:webOS] library.json\n", library.exportJSON());
              setNote("Der Bibliotheksstand steht im Web-Inspector-Protokoll.");
            }}
          />
          <Row
            route={ROUTE}
            area="data"
            id="import"
            label="Bibliothek einlesen"
            hint="JSON einfügen — wird zusammengeführt, nichts wird gelöscht"
            value=""
            chevron
            onClick={() => {
              const raw = window.prompt("Bibliothek einlesen (JSON einfügen)");
              if (!raw) return;
              try {
                const result = library.importJSON(raw);
                setNote(`Zusammengeführt: ${result.favorites} auf der Merkliste, ${folgen(result.progress)} mit Fortschritt.`);
              } catch (cause) {
                setNote(`Nicht lesbar: ${(cause as Error)?.message ?? "ungültiges JSON"}`);
              }
            }}
          />
        </section>

        <section className="setting-card" data-nav-row="" aria-label="Zurücksetzen">
          <h3>Zurücksetzen</h3>
          <Row route={ROUTE} area="data" id="clear-history" label="Verlauf leeren" hint="Zuletzt geöffnete Titel" value="" chevron onClick={() => setConfirm("history")} />
          <Row route={ROUTE} area="data" id="clear-progress" label="Fortschritt löschen" hint="Alle Folgen gelten danach als ungesehen" value="" chevron onClick={() => setConfirm("progress")} />
          <Row route={ROUTE} area="data" id="reset" label="Geräteeinstellungen zurücksetzen" hint="Server, TMDB-Weg, Player-Bedienung" value="" chevron onClick={() => setConfirm("reset")} />
          {note ? <p className="card-note strong" role="status">{note}</p> : null}
        </section>
      </div>

      <Dialog
        open={confirm !== null}
        onClose={() => setConfirm(null)}
        eyebrow="Daten"
        title={confirm === "history" ? "Verlauf leeren?" : confirm === "progress" ? "Fortschritt löschen?" : "Einstellungen zurücksetzen?"}
        id="data-confirm"
        initial='[data-focus-key="confirm-cancel"]'
      >
        <p className="dialog-text">
          {confirm === "progress"
            ? "Mit Google Drive wird die Löschung auf alle Geräte übertragen."
            : "Das lässt sich nicht rückgängig machen."}
        </p>
        <div className="dialog-actions">
          <SpotButton className="hero-btn" focusKey="confirm-cancel" onClick={() => setConfirm(null)}>Abbrechen</SpotButton>
          <SpotButton className="hero-btn primary" focusKey="confirm-run" onClick={run}>Ausführen</SpotButton>
        </div>
      </Dialog>
    </Screen>
  );
}
