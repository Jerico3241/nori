// Der Zustand von TMDB in drei Wörtern — und was dahinter steckt.
//
// „Verbunden" heißt: TMDB hat zuletzt geantwortet. Nicht: ein Schlüssel ist
// eingetragen. Ein Fernseher ohne Netz mit mitgeliefertem Schlüssel ist nicht
// verbunden, und die Oberfläche sagt das.

import { useEffect, useState } from "react";
import { tmdb, type TmdbDiagnostics } from "./tmdb";

export type TmdbTone = "ok" | "idle" | "warn" | "error";

export interface TmdbState {
  label: "Verbunden" | "Nicht verfügbar" | "Fehler" | "Bereit";
  tone: TmdbTone;
  detail: string;
}

export function tmdbState(diagnostics: Pick<TmdbDiagnostics, "available" | "lastStatus">): TmdbState {
  if (!diagnostics.available) {
    return { label: "Nicht verfügbar", tone: "warn", detail: "TMDB ist ausgeschaltet — Nori zeigt die Daten der Quellen." };
  }
  switch (diagnostics.lastStatus) {
    case "ok":
      return { label: "Verbunden", tone: "ok", detail: "TMDB hat zuletzt geantwortet." };
    case "unauthorized":
      return { label: "Fehler", tone: "error", detail: "Schlüssel abgelehnt (401/403)." };
    case "rateLimited":
      return { label: "Fehler", tone: "error", detail: "Zu viele Anfragen (429) — Nori wartet und versucht es später." };
    case "notFound":
      return { label: "Fehler", tone: "error", detail: "Der Weg zu TMDB antwortet mit 404 — ein Nori-Server ohne TMDB?" };
    case "unavailable":
      return { label: "Nicht verfügbar", tone: "warn", detail: "TMDB ist gerade nicht erreichbar." };
    case "noKey":
      return { label: "Nicht verfügbar", tone: "warn", detail: "Kein Zugang eingerichtet." };
    default:
      return { label: "Bereit", tone: "idle", detail: "Noch nicht abgefragt." };
  }
}

/**
 * Der TMDB-Zustand, neu gezeichnet genau dann, wenn er sich ändert.
 *
 * Vorher lasen die Einstellungen ihn alle drei Sekunden neu — ein Rendern der
 * ganzen Seite, auch wenn TMDB seit Minuten nichts getan hatte.
 */
export function useTmdbState(): TmdbState {
  const [state, setState] = useState(() => tmdbState(tmdb.status()));
  useEffect(() => {
    const update = () => setState((current) => {
      const next = tmdbState(tmdb.status());
      return next.label === current.label && next.tone === current.tone && next.detail === current.detail
        ? current
        : next;
    });
    // Zwischen dem ersten Rendern und diesem Effekt kann sich der Zugang schon
    // geändert haben.
    update();
    return tmdb.subscribeStatus(update);
  }, []);
  return state;
}
