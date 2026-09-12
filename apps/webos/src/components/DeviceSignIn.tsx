// Google Drive verbinden — der Gerätefluss als eigener Dialog.
//
// Was hier passiert, ist eine Handlung mit einem zweiten Gerät und dauert eine
// Minute. Sie bekommt deshalb die ganze Fläche und keine Zeile in einer Liste.
// Drei Dinge stehen darauf, in dieser Reihenfolge:
//
// 1. **Der QR-Code.** Groß, mit hellem Grund und Rand. Enthält Google eine
//    vollständige Adresse (`verification_uri_complete` nach RFC 8628), steckt
//    der Code schon darin und am Telefon ist nichts mehr zu tippen.
// 2. **Die Adresse und der Code**, für den, der kein Telefon mit Kamera dabei
//    hat — beide aus drei Metern lesbar.
// 3. **Wie lange der Code noch gilt.** Ohne das wartet jemand vor einem
//    Bildschirm, auf dem längst nichts mehr passieren kann.
//
// Kein OAuth-Wort, keine Fehlernummer. Zurück bricht die Anmeldung ab und
// schließt den Dialog, nicht die Seite darunter; der Fokus kehrt über
// `SpotArea` an den Knopf zurück, der den Dialog geöffnet hat.

import { useEffect, useRef, useState } from "react";

import { useBackHandler } from "../navigation/back";
import { SpotArea, SpotButton, focusWithin } from "../navigation/Spot";
import { useSync } from "../state/sync";
import { QrCode } from "./QrCode";

export function DeviceSignInDialog() {
  const sync = useSync();
  const panel = useRef<HTMLDivElement>(null);

  // Die Restlaufzeit wird bei jedem Zeichnen aus `expiresAt` gerechnet; der
  // Zeitgeber löst nur das Neuzeichnen aus. Gespeichert begann sie bei null,
  // und für ein Bild stand „abgelaufen" auf dem Bildschirm.
  const expiresAt = sync.pending?.expiresAt ?? 0;
  const [, redraw] = useState(0);
  useEffect(() => {
    if (!expiresAt) return undefined;
    const timer = window.setInterval(() => redraw((n) => n + 1), 1000);
    return () => window.clearInterval(timer);
  }, [expiresAt]);
  const remaining = expiresAt ? Math.max(0, Math.round((expiresAt - Date.now()) / 1000)) : 0;

  useBackHandler(() => {
    sync.cancelConnect();
    return true;
  });

  useEffect(() => focusWithin(panel.current), []);

  // Läuft der Code ab, wandert der Fokus auf „Neuen Code erzeugen" — auch wenn
  // er schon auf „Abbrechen" im Dialog stand, dem einen Knopf, der dann nicht
  // weiterhilft.
  const expired = sync.expired || (expiresAt > 0 && expiresAt <= Date.now());
  useEffect(() => {
    if (!expired) return undefined;
    return focusWithin(panel.current, '[data-focus-key="device-retry"]', 20, true);
  }, [expired]);

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
          <div className="eyebrow">Synchronisierung</div>
          <h2>Google Drive verbinden</h2>

          {expired ? (
            <div className="device-expired">
              <p className="device-lead">Der Anmeldecode ist abgelaufen.</p>
              <p className="device-hint">Codes gelten nur wenige Minuten. Ein neuer ist sofort da.</p>
            </div>
          ) : (
            <div className="device-body">
              <div className="device-qr">
                {/* Genau die Adresse, die Google geliefert hat — nie eine selbst gebaute. */}
                <QrCode value={sync.qrPayload ?? sync.pending.verificationUrl} label={`QR-Code für ${shortUrl}`} />
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
              <SpotButton className="hero-btn primary" focusKey="device-retry" onClick={() => sync.connect()}>
                Neuen Code erzeugen
              </SpotButton>
            ) : null}
            <SpotButton className="hero-btn" focusKey="device-cancel" onClick={() => sync.cancelConnect()}>
              Abbrechen
            </SpotButton>
          </div>
        </div>
      </SpotArea>
    </>
  );
}

/**
 * Die verstrichene Zeit in Worten.
 *
 * „vor wenigen Sekunden" statt „vor 3 Sekunden": die Zeile wird nicht jede
 * Sekunde neu gezeichnet, und eine Zahl, die eine Minute stehen bleibt, ist
 * falsch.
 */
export function relativeTime(stamp: number): string {
  const seconds = Math.max(0, Math.round((Date.now() - stamp) / 1000));
  if (seconds < 45) return "vor wenigen Sekunden";
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return minutes === 1 ? "vor einer Minute" : `vor ${minutes} Minuten`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return hours === 1 ? "vor einer Stunde" : `vor ${hours} Stunden`;
  const days = Math.round(hours / 24);
  return days === 1 ? "gestern" : `vor ${days} Tagen`;
}
