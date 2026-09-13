// Mehr → Abgleich über Google Drive.
//
// Abgeglichen werden Merkliste, Verlauf, Fortschritt und Einstellungen — keine
// Videos. Jedes Gerät schreibt nur seine eigene Datei; der Fernseher liest und
// schreibt dabei ausschliesslich den sichtbaren TV-Spiegel im Ordner „Nori".
// Die Regeln stehen in `docs/synchronisation.md`.
//
// Liegt dort noch kein iPhone, iPad oder Mac, sagt die Seite in einem Satz, wo
// „Mit Fernseher teilen" einzuschalten ist — ohne OAuth-Begriffe.
//
// **Die Anmeldung ist ein Knopf.** Client-ID und Client-Secret kommen aus dem
// Build und sind keine Einstellung: sie mit einer Fernbedienung über eine
// Bildschirmtastatur einzugeben war keine Einrichtung, sondern eine Hürde.
// Fehlen sie, sagt die Seite das in einem Satz. Welche Werte ein Paket benutzt,
// steht nur mit eingeschaltetem „Diagnoseprotokoll" da, und das Secret auch
// dann nicht.
//
// „Dieses Gerät trennen" und „Google-Zugriff widerrufen" sind zwei Dinge. Das
// Zweite betrifft alle Geräte am Konto und fragt vorher — in einem Dialog der
// App, nicht über `window.confirm`, das auf einem Fernseher nicht zuverlässig
// bedienbar ist.

import { useEffect, useState } from "react";

import { DeviceSignInDialog, relativeTime } from "../../components/DeviceSignIn";
import { Dialog } from "../../components/Overlay";
import { Screen } from "../../components/Screen";
import { restoreFocusSoon } from "../../navigation/focusMemory";
import { useTick } from "../../hooks/useTick";
import { SpotButton } from "../../navigation/Spot";
import { useSettings } from "../../state/settings";
import { syncStatusLabel, useSync } from "../../state/sync";
import { Info } from "../More";

const ROUTE = "more-sync";

export function SyncPage() {
  const sync = useSync();
  const { settings } = useSettings();
  const [confirmRevoke, setConfirmRevoke] = useState(false);
  // „vor 3 Minuten" soll auch nach drei Minuten auf der Seite noch stimmen.
  useTick(30_000, sync.lastSuccessfulSync !== null);

  useEffect(() => restoreFocusSoon(ROUTE, ["sync"], { initial: ".setting-card .spottable", ready: true }), []);

  const tone = sync.status === "idle" ? "ok"
    : sync.status === "error" || sync.needsReauthorization ? "error" : "idle";
  const connected = sync.isConfigured && !sync.needsReauthorization
    && sync.status !== "disconnected" && sync.status !== "authorizing";

  return (
    <Screen route={ROUTE} eyebrow="Mehr" title="Abgleich" className="more-sub">
      <div className="settings-grid single">
        <section className="setting-card" aria-label="Google Drive">
          <h3>Google Drive</h3>
          <p className="card-note">
            Merkliste, Verlauf, Fortschritt und Einstellungen mit iPhone, iPad und Mac teilen —
            keine Videos. Ohne Netz funktioniert Nori vollständig weiter.
          </p>
          <Info label="Zustand" value={syncStatusLabel(sync)} tone={tone} />
          {connected && sync.lastSuccessfulSync ? (
            <Info label="Letzte Synchronisierung" value={relativeTime(sync.lastSuccessfulSync)} tone="idle" />
          ) : null}

          {!sync.isConfigured ? (
            <p className="card-note strong">
              Diese Nori-Fassung wurde ohne Google-Abgleich gebaut. Merkliste, Verlauf und
              Fortschritt funktionieren vollständig weiter — sie bleiben auf diesem Fernseher.
            </p>
          ) : (
            <div className="card-actions">
              {sync.needsReauthorization ? (
                <SpotButton className="hero-btn primary" focusRoute={ROUTE} focusArea="sync" focusKey="reconnect" onClick={() => sync.connect()}>
                  Erneut anmelden
                </SpotButton>
              ) : sync.status === "disconnected" || sync.status === "authorizing" ? (
                <SpotButton className="hero-btn primary" focusRoute={ROUTE} focusArea="sync" focusKey="connect" onClick={() => sync.connect()}>
                  Mit Google Drive verbinden
                </SpotButton>
              ) : (
                <>
                  <SpotButton className="hero-btn primary" focusRoute={ROUTE} focusArea="sync" focusKey="sync-now" onClick={() => sync.syncNow()}>
                    Jetzt synchronisieren
                  </SpotButton>
                  <SpotButton className="hero-btn" focusRoute={ROUTE} focusArea="sync" focusKey="disconnect" onClick={() => sync.disconnect()}>
                    Dieses Gerät trennen
                  </SpotButton>
                  <SpotButton className="hero-btn" focusRoute={ROUTE} focusArea="sync" focusKey="revoke" onClick={() => setConfirmRevoke(true)}>
                    Google-Zugriff widerrufen
                  </SpotButton>
                </>
              )}
            </div>
          )}

          {sync.needsReauthorization ? <p className="card-note strong">Google Drive muss erneut verbunden werden.</p> : null}
          {sync.message ? <p className="card-note strong" role="alert">{sync.message}</p> : null}
          {sync.lastWarning ? <p className="card-note">{sync.lastWarning}</p> : null}
          {connected && sync.tvMirrorMissing ? (
            <p className="card-note strong" role="status">
              Noch keine TV-Synchronisation gefunden – Aktiviere auf deinem iPhone, iPad oder Mac in Nori
              unter Synchronisation „Mit Fernseher teilen“.
            </p>
          ) : null}
          {connected ? (
            <p className="card-note">
              Nori legt dafür im Ordner „Nori“ in deinem Google Drive eine Datei an. Aktuell bleibt der
              Fernseher, solange mindestens ein iPhone, iPad oder Mac mit „Mit Fernseher teilen“
              regelmäßig synchronisiert.
            </p>
          ) : null}

          {/* Nur mit dem Diagnoseschalter. Das Client-Secret steht hier nicht, auch
              nicht verkürzt — dass es vorhanden ist, reicht als Auskunft. */}
          {settings.debug ? (
            <>
              <p className="card-note">
                Client-ID: {sync.diagnostics.clientId || "—"} ·{" "}
                {sync.diagnostics.origin === "build" ? "aus dem Build"
                  : sync.diagnostics.origin === "migrated" ? "aus einer früheren Fassung übernommen"
                    : "fehlt"} · Client-Secret: {sync.diagnostics.hasSecret ? "vorhanden" : "fehlt"} · Bereich: nur
                drive.file
              </p>
              {sync.diagnostics.origin === "migrated" ? (
                <div className="card-actions">
                  <SpotButton className="hero-btn" focusRoute={ROUTE} focusArea="sync" focusKey="credentials-clear" onClick={() => sync.forgetMigratedCredentials()}>
                    Übernommene Zugangsdaten verwerfen
                  </SpotButton>
                </div>
              ) : null}
            </>
          ) : null}
        </section>
      </div>

      <Dialog open={confirmRevoke} onClose={() => setConfirmRevoke(false)} eyebrow="Abgleich" title="Google-Zugriff widerrufen?" id="revoke" initial='[data-focus-key="revoke-cancel"]'>
        <p className="dialog-text">
          Dadurch kann Nori auf deinen Geräten nicht mehr auf die Google-Drive-Synchronisierung
          zugreifen — auch iPhone und Mac nicht. Deine lokale Bibliothek bleibt erhalten.
        </p>
        <div className="dialog-actions">
          <SpotButton className="hero-btn" focusKey="revoke-cancel" onClick={() => setConfirmRevoke(false)}>
            Abbrechen
          </SpotButton>
          <SpotButton
            className="hero-btn primary"
            focusKey="revoke-confirm"
            onClick={() => {
              sync.revokeAccess();
              setConfirmRevoke(false);
            }}
          >
            Zugriff widerrufen
          </SpotButton>
        </div>
      </Dialog>

      {sync.pending ? <DeviceSignInDialog /> : null}
    </Screen>
  );
}
