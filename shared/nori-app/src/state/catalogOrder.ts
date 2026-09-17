// Die Reihenfolge des Katalogs über das Aushängen der Seite hinaus.
//
// Die Katalogseite wird beim Öffnen einer Detailseite ausgehängt. Wer danach
// „Zurück" drückt, kehrt in **dieselbe** Ansicht zurück — mit derselben
// Reihenfolge, damit Fokus und Scrollstand auf dieselbe Karte an derselben
// Stelle treffen. Wer den Katalog dagegen neu öffnet (Seitenleiste), bekommt
// eine frische Sortierung mit allem, was TMDB inzwischen weiß.
//
// Nur im Arbeitsspeicher, wie `usePersistentState`.

import type { CatalogOrder, HomeCandidate } from "@nori/core";

export interface CatalogOrderSession {
  order: CatalogOrder | null;
  /**
   * Die zuletzt bekannten Daten je Kennung. Eine Karte, die in der Ansicht
   * steht, aber nach einem TMDB-Treffer nicht mehr unter den frisch
   * zusammengeführten Titeln ist, zeichnet sich damit weiter.
   */
  known: Map<string, HomeCandidate>;
}

const sessions = new Map<string, CatalogOrderSession>();

/** `fresh` beim erneuten Öffnen — dann beginnt die Ansicht mit neuer Reihenfolge. */
export function catalogOrderSession(route: string, fresh: boolean): CatalogOrderSession {
  if (fresh) sessions.delete(route);
  let session = sessions.get(route);
  if (!session) {
    session = { order: null, known: new Map() };
    sessions.set(route, session);
  }
  return session;
}
