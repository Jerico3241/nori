// Ein QR-Code auf dem Fernseher.
//
// Gerechnet wird er im Gerät (`shared/nori-core/src/qr.ts`) und nicht bei
// einem Dienst im Netz. Das ist keine Sparsamkeit: die Adresse, die hier
// abgebildet wird, gehört zu einer laufenden Anmeldung, und sie an einen
// Dritten zu schicken wäre genau die Art Datenweitergabe, die beim Anmelden
// nicht passieren darf.
//
// Ein einzelner `<path>` statt tausend Rechtecke — auf einem Fernseher von
// 2019 ist jeder DOM-Knoten teuer, und ein Code der Fassung 4 hätte über
// tausend davon.
//
// `shape-rendering="crispEdges"` ist der Punkt, an dem ein QR-Code auf einem
// Fernseher lesbar wird oder nicht: ohne das glättet der Browser die Kanten,
// und bei einem Modul von wenigen Bildpunkten verschwimmen hell und dunkel
// ineinander. Eine Kamera findet dann nichts.

import { encodeQrCode, qrSvgPath } from "@nori/core";
import { useMemo } from "react";

import { warn } from "../services/log";

export interface QrCodeProps {
  /** Genau die Adresse, die Google geliefert hat. Nie eine gebaute. */
  value: string;
  /** Beschriftung für Sprachausgabe — der Code selbst ist ein Bild. */
  label?: string;
}

/**
 * Der ruhige Rand um den Code.
 *
 * Die Norm verlangt vier Module. Ohne ihn erkennt eine Kamera die Grenze des
 * Codes nicht, und auf einem dunklen Hintergrund ist „ohne Rand" der
 * Normalfall, nicht die Ausnahme.
 */
const QUIET_ZONE = 4;

export function QrCode({ value, label }: QrCodeProps) {
  const code = useMemo(() => {
    try {
      return encodeQrCode(value);
    } catch (cause) {
      // Kein Absturz der Seite wegen eines Bildes. Der Code steht daneben in
      // Ziffern, und damit kommt der Nutzer auch ohne QR weiter.
      warn("app", "QR-Code nicht darstellbar", cause);
      return null;
    }
  }, [value]);

  if (!code) return null;

  const span = code.size + QUIET_ZONE * 2;
  return (
    <svg
      className="qr"
      viewBox={`0 0 ${span} ${span}`}
      role="img"
      aria-label={label ?? "QR-Code zur Anmeldung"}
      shapeRendering="crispEdges"
    >
      {/* Weiss und nicht durchsichtig: der Code braucht seinen hellen Grund,
          und die Oberfläche ist dunkel. */}
      <rect x="0" y="0" width={span} height={span} fill="#ffffff" />
      <g transform={`translate(${QUIET_ZONE} ${QUIET_ZONE})`}>
        <path d={qrSvgPath(code)} fill="#05060a" />
      </g>
    </svg>
  );
}
