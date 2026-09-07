// Ladezustand, Fehlerzustand, Leerzustand.
//
// Auf einem Fernseher gibt es keinen Ladebalken im Browserrahmen und keine
// Konsole: was die App nicht selbst zeigt, sieht niemand. Deshalb hat jede
// Abfrage alle drei Enden.

import type { ReactNode } from "react";
import { SpotButton } from "../navigation/Spot";

export function RailSkeleton({ count = 7 }: { count?: number }) {
  return (
    <div className="rail-track" aria-hidden="true">
      {Array.from({ length: count }, (_, index) => (
        <div className="media-card skeleton" key={index}>
          <div className="poster skeleton-block" />
          <div className="skeleton-line" />
        </div>
      ))}
    </div>
  );
}

export function GridSkeleton({ count = 18 }: { count?: number }) {
  return (
    <div className="media-grid" aria-hidden="true">
      {Array.from({ length: count }, (_, index) => (
        <div className="media-card skeleton" key={index}>
          <div className="poster skeleton-block" />
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
        <SpotButton className="primary" onClick={onRetry} focusKey={retryFocusKey ?? "retry"}>
          Erneut versuchen
        </SpotButton>
      ) : null}
    </div>
  );
}

export function OfflineState({ onRetry }: { onRetry: () => void }) {
  return (
    <ErrorState
      title="Keine Verbindung"
      message="Nori konnte keine Verbindung zum Server herstellen. Prüfe die Netzwerkverbindung des Fernsehers und die Serveradresse in den Einstellungen."
      onRetry={onRetry}
      retryFocusKey="offline-retry"
    />
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
