// Mehr → Abgleich über Google Drive.
//
// Abgeglichen werden Merkliste, Verlauf, Fortschritt und Einstellungen — keine
// Videos. Jedes Gerät schreibt nur seine eigene Datei im versteckten
// `appDataFolder`; die Regeln stehen in `docs/synchronisation.md`.
//
// Die Anmeldung läuft über den Gerätecode: der Fernseher zeigt Adresse und
// Code, eingegeben wird auf dem Smartphone. Die Fernbedienung tippt keine
// Zugangsdaten.
//
// „Dieses Gerät trennen" und „Google-Zugriff widerrufen" sind zwei Dinge. Das
// Zweite betrifft alle Geräte am Konto und fragt deshalb vorher — in einem
// Dialog der App, nicht über `window.confirm`, das auf einem Fernseher nicht
// zuverlässig bedienbar ist.

import { useEffect, useState } from "react";

import { Dialog } from "../../components/Overlay";
import { Screen } from "../../components/Screen";
import { rememberFocus, restoreFocusSoon } from "../../navigation/focusMemory";
import { SpotButton } from "../../navigation/Spot";
import { syncStatusLabel, useSync } from "../../state/sync";
import { Info } from "../More";

const ROUTE = "more-sync";

export function SyncPage() {
  const sync = useSync();
  const [clientIdDraft, setClientIdDraft] = useState("");
  const [clientSecretDraft, setClientSecretDraft] = useState("");
  const [credentialsNote, setCredentialsNote] = useState<string | null>(null);
  const [confirmRevoke, setConfirmRevoke] = useState(false);

  useEffect(() => restoreFocusSoon(ROUTE, ["sync"], { initial: ".setting-card .spottable", ready: true }), []);

  const tone = sync.status === "idle" ? "ok" : sync.status === "error" ? "error" : "idle";

  return (
    <Screen route={ROUTE} eyebrow="Mehr" title="Abgleich" className="more-sub">
      <div className="settings-grid single">
        <section className="setting-card" aria-label="Google Drive">
          <h3>Google Drive</h3>
          <Info label="Zustand" hint="Merkliste, Verlauf, Fortschritt und Einstellungen — keine Videos" value={syncStatusLabel(sync)} tone={tone} />
          {sync.lastSuccessfulSync ? (
            <Info label="Zuletzt abgeglichen" value={new Date(sync.lastSuccessfulSync).toLocaleString("de-DE")} tone="idle" />
          ) : null}

          {!sync.isConfigured ? (
            <>
              <p className="card-note">
                Für die Anmeldung braucht Nori die Zugangsdaten eines eigenen Google-Cloud-Projekts
                (OAuth-Client vom Typ „Fernseher und Geräte mit eingeschränkter Eingabe“). Die
                Schritte stehen in docs/google-drive-sync.md. Ohne Abgleich bleibt die Bibliothek
                vollständig auf diesem Fernseher.
              </p>
              <label className="field">
                <span>Google-Client-ID</span>
                <input
                  className="spottable text-field"
                  data-focus-key="client-id"
                  type="text"
                  value={clientIdDraft}
                  placeholder="123456-abc.apps.googleusercontent.com"
                  aria-label="Google-Client-ID"
                  onFocus={() => rememberFocus(ROUTE, "sync", "client-id")}
                  onChange={(event) => setClientIdDraft(event.target.value)}
                />
              </label>
              <label className="field">
                <span>Client-Secret — liegt unverschlüsselt im Speicher dieser App</span>
                <input
                  className="spottable text-field"
                  data-focus-key="client-secret"
                  type="password"
                  value={clientSecretDraft}
                  placeholder="GOCSPX-…"
                  aria-label="Google-Client-Secret"
                  onFocus={() => rememberFocus(ROUTE, "sync", "client-secret")}
                  onChange={(event) => setClientSecretDraft(event.target.value)}
                />
              </label>
              <div className="card-actions">
                <SpotButton
                  className="hero-btn primary"
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
              {credentialsNote ? <p className="card-note strong" role="alert">{credentialsNote}</p> : null}
            </>
          ) : sync.pending ? (
            <DeviceCode />
          ) : (
            <div className="card-actions">
              {sync.status === "disconnected" ? (
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
              {sync.credentialsFromDevice ? (
                <SpotButton className="hero-btn" focusRoute={ROUTE} focusArea="sync" focusKey="credentials-clear" onClick={() => sync.clearCredentials()}>
                  Zugangsdaten entfernen
                </SpotButton>
              ) : null}
            </div>
          )}

          {sync.message ? <p className="card-note strong" role="alert">{sync.message}</p> : null}
          {sync.lastWarning ? <p className="card-note">{sync.lastWarning}</p> : null}
        </section>
      </div>

      <Dialog open={confirmRevoke} onClose={() => setConfirmRevoke(false)} eyebrow="Abgleich" title="Google-Zugriff widerrufen?" id="revoke" initial='[data-focus-key="revoke-cancel"]'>
        <p className="dialog-text">
          Damit verlieren alle Geräte an diesem Google-Konto den Zugriff — auch iPhone und Mac.
          Die Bibliothek auf diesem Fernseher bleibt erhalten.
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
    </Screen>
  );
}

/** Der Gerätefluss, so groß, dass man ihn vom Sofa aus lesen kann. */
function DeviceCode() {
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
      <p className="card-note strong">Öffne diese Adresse auf deinem Smartphone oder Computer und gib den Code ein:</p>
      <p className="device-code-url">{sync.pending.verificationUrl}</p>
      <p className="device-code-value">{sync.pending.userCode}</p>
      <p className="card-note">
        {remaining > 0
          ? `Der Code gilt noch ${minutes}:${seconds} Minuten. Nori wartet auf deine Bestätigung …`
          : "Der Code ist abgelaufen. Bitte neu beginnen."}
      </p>
      <div className="card-actions">
        <SpotButton className="hero-btn" focusRoute={ROUTE} focusArea="sync" focusKey="cancel" onClick={() => sync.cancelConnect()}>
          Abbrechen
        </SpotButton>
      </div>
    </div>
  );
}
