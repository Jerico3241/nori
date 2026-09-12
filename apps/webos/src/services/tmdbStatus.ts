// Der Zustand von TMDB in drei Wörtern — und was dahinter steckt.
//
// „Verbunden" heißt: TMDB hat zuletzt geantwortet. Nicht: ein Schlüssel ist
// eingetragen. Ein Fernseher ohne Netz mit mitgeliefertem Schlüssel ist nicht
// verbunden, und die Oberfläche sagt das.

import type { TmdbDiagnostics } from "./tmdb";

export type TmdbTone = "ok" | "idle" | "warn" | "error";

export interface TmdbState {
  label: "Verbunden" | "Nicht verfügbar" | "Fehler" | "Bereit";
  tone: TmdbTone;
  detail: string;
}

export function tmdbState(diagnostics: TmdbDiagnostics): TmdbState {
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
