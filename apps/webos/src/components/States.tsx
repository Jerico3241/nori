// Ladezustand, Fehlerzustand, Leerzustand.
//
// Auf einem Fernseher gibt es keinen Ladebalken im Browserrahmen und keine
// Konsole: was die App nicht selbst zeigt, sieht niemand. Die Platzhalter haben
// dieselben Maße wie die Karten, die sie ersetzen — beim Eintreffen der Daten
// springt nichts.

import type { ReactNode } from "react";
import { SpotButton } from "../navigation/Spot";

export function RailSkeleton({ count = 6, wide = false }: { count?: number; wide?: boolean }) {
  return (
    <div className="rail" aria-hidden="true">
      <div className="rail-inner">
        {Array.from({ length: count }, (_, index) => (
          <div className={`${wide ? "land-card" : "poster-card"} skeleton`} key={index}>
            <div className={`card-art ${wide ? "land-art" : "poster-art"}`} />
            <div className="skeleton-line" />
          </div>
        ))}
      </div>
    </div>
  );
}

export function GridSkeleton({ count = 10, className = "catalog-grid" }: { count?: number; className?: string }) {
  return (
    <div className={className} aria-hidden="true">
      {Array.from({ length: count }, (_, index) => (
        <div className="poster-card skeleton" key={index}>
          <div className="card-art poster-art" />
          <div className="skeleton-line" />
        </div>
      ))}
    </div>
  );
}

export function ErrorState({ title, message, onRetry, retryFocusKey }: {
  title: string;
  message: string;
  onRetry?: () => void;
  retryFocusKey?: string;
}) {
  return (
    <div className="state-panel" role="alert">
      <h2>{title}</h2>
      <p>{message}</p>
      {onRetry ? (
        <SpotButton className="hero-btn primary" onClick={onRetry} focusKey={retryFocusKey ?? "retry"}>
          Erneut versuchen
        </SpotButton>
      ) : null}
    </div>
  );
}

export function EmptyState({ title, message, action }: {
  title: string;
  message: string;
  action?: ReactNode;
}) {
  return (
    <div className="state-panel">
      <h2>{title}</h2>
      <p>{message}</p>
      {action}
    </div>
  );
}
