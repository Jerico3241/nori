// Hilfsfunktionen der Parser — dieselben wie in `HTML.swift`.

import { attr, nilIfEmpty, text } from "../dom.js";
import type { AiringEntry, CalendarPayload, CatalogItem } from "../models.js";

/** Reihenfolge erhalten, Leeres und Dubletten raus. */
export function unique(list: (string | null | undefined)[]): string[] {
  const out: string[] = [];
  for (const raw of list) {
    const t = (raw ?? "").trim();
    if (t && !out.includes(t)) out.push(t);
  }
  return out;
}

/**
 * Aus einem beliebigen `href` den Nori-Pfad machen.
 *
 * Beide Quellen mischen absolute URLs, Query-Anhänge und HTML-Entities in ihre
 * Links; alles unterhalb dieser Funktion darf sich auf einen sauberen Pfad
 * verlassen.
 */
export function toAniworldPath(href: string): string {
  const cleaned = href.replace(/&amp;/g, "&").trim();
  const anime = cleaned.match(/\/anime\/stream\/[^?\s#]+/);
  if (anime) return anime[0].replace(/\/+$/, "");
  const serie = cleaned.match(/\/serie\/[^?\s#]+/);
  if (serie) return serie[0].replace(/\/+$/, "");
  const redirect = cleaned.match(/\/redirect\/\d+/);
  if (redirect) return redirect[0];
  if (cleaned.startsWith("/r")) return cleaned.split("#")[0];
  if (cleaned.startsWith("/")) return cleaned.split("?")[0];
  return "";
}

export function flagLabel(title: string): string | null {
  const t = title.toLowerCase();
  if (t.includes("untertitel") || t.includes("gersub") || t.includes("japanese-german")) return "GerSub";
  if (t.includes("english") || t.includes("englisch")) return "EN";
  if (t.includes("deutsch") || t.includes("german")) return "DE";
  if (t.includes("japan")) return "JP";
  return nilIfEmpty(title);
}

export function langLabel(key: string): string {
  switch (key) {
    case "1": return "DE";
    case "2": return "EN";
    case "3": return "GerSub";
    default: return key;
  }
}

/** Lazy-Load-Adressen vor Platzhaltern lesen; absolute URLs und Queries erhalten. */
export function sourcePoster(doc: Document, pathMarker: string, selector: string): string | null {
  for (const img of Array.from(doc.querySelectorAll(selector))) {
    for (const attribute of ["data-src", "data-original", "src"]) {
      const value = attr(img, attribute);
      if (value.includes(pathMarker) && !value.startsWith("data:")) return value;
    }
  }
  const og = attr(doc.querySelector("meta[property='og:image']"), "content");
  return og.includes(pathMarker) ? og : null;
}

export function slugFromHref(href: string): string | null {
  const cleaned = href.replace(/&amp;/g, "&");
  const anime = cleaned.match(/\/anime\/stream\/([^/?#]+)/);
  if (anime) return anime[1];
  const serie = cleaned.match(/\/serie\/([^/?#]+)/);
  if (serie) return serie[1];
  return null;
}

/**
 * Notnagel, wenn ein Kalendereintrag keine URL mitliefert.
 *
 * Nur die Endung abschneiden: `split(".")[0]` machte aus „one.piece.jpg" den
 * Slug „one" — genau die falschen Verweise, die das hier verhindern soll.
 */
export function slugFromPoster(poster: string): string | null {
  const file = poster.split("/").pop() ?? poster;
  const dot = file.lastIndexOf(".");
  const base = dot > 0 ? file.slice(0, dot) : file;
  const trimmed = base.replace(/^[-_ ]+|[-_ ]+$/g, "").toLowerCase();
  if (trimmed.length < 3) return null;
  if (!/[a-z]/.test(trimmed)) return null;
  if (!/^[a-z0-9-]+$/.test(trimmed)) return null;
  return trimmed;
}

/**
 * Nur übernehmen, was tatsächlich eine Adresse ist. Das Feld enthält je nach
 * Datensatz einen Pfad, eine volle URL oder nur einen Dateinamen — aus letzterem
 * lässt sich keine gültige Adresse bauen.
 */
export function coverPathFromCalendar(poster: string): string | null {
  const trimmed = poster.trim();
  if (!trimmed) return null;
  if (trimmed.startsWith("http://") || trimmed.startsWith("https://") || trimmed.startsWith("/")) {
    return trimmed;
  }
  return null;
}

const ANIME_WORDS = /\b(anime|ova|ona|shounen|shoujo|seinen|isekai|zeichentrick|the animation)\b/i;

/** Serienstream führt auch Anime; die gehören in den Anime-Katalog, nicht hierher. */
export function dropAnimeTitles(items: CatalogItem[]): CatalogItem[] {
  return items.filter((item) => {
    const hay = `${item.title} ${item.alts.join(" ")} ${item.genres.join(" ")}`;
    if (ANIME_WORDS.test(hay)) return false;
    for (const ch of hay) {
      const code = ch.codePointAt(0) ?? 0;
      if ((code >= 0x3040 && code <= 0x30ff) || (code >= 0x3400 && code <= 0x9fff)) return false;
    }
    return true;
  });
}

export const MONTH_NAMES = [
  "", "Januar", "Februar", "März", "April", "Mai", "Juni",
  "Juli", "August", "September", "Oktober", "November", "Dezember",
];

const WEEKDAY_NAMES = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"];

/**
 * Ein Zeitpunkt in Europa/Berlin als Millisekunden seit 1970.
 *
 * Kein `new Date(y, m, d)`: das rechnet in der Zeitzone des Fernsehers, und ein
 * Kalender, der je nach Gerätestandort andere Tage zeigt, ist kein Kalender.
 * Der Offset wird über `Intl` ermittelt und einmal nachkorrigiert — das ist auch
 * an der Zeitumstellung genau.
 */
export function berlinTime(
  year: number, month: number, day: number, hour = 0, minute = 0,
): number {
  const guess = Date.UTC(year, month - 1, day, hour, minute);
  const offset = berlinOffsetMs(guess);
  const exact = guess - offset;
  // Zweiter Durchgang: an der Umstellungsstunde liegt der erste Offset daneben.
  const corrected = guess - berlinOffsetMs(exact);
  return corrected;
}

const berlinFormat = new Intl.DateTimeFormat("en-US", {
  timeZone: "Europe/Berlin",
  hour12: false,
  year: "numeric", month: "2-digit", day: "2-digit",
  hour: "2-digit", minute: "2-digit", second: "2-digit",
});

function berlinOffsetMs(utcMs: number): number {
  const parts = berlinFormat.formatToParts(new Date(utcMs));
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? "0");
  const asUTC = Date.UTC(
    get("year"), get("month") - 1, get("day"),
    get("hour") % 24, get("minute"), get("second"),
  );
  return asUTC - utcMs;
}

export function berlinWeekday(year: number, month: number, day: number): string {
  const date = new Date(berlinTime(year, month, day, 12));
  return WEEKDAY_NAMES[date.getUTCDay()] ?? "";
}

export function berlinStartOfDay(nowMs: number): number {
  const parts = berlinFormat.formatToParts(new Date(nowMs));
  const get = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? "0");
  return berlinTime(get("year"), get("month"), get("day"), 0, 0);
}

/**
 * Sortieren und in „kommt" / „gerade gelaufen" teilen.
 *
 * Die Grenzen sind aus dem Swift-Kern: drei Stunden Nachlauf für „kommt",
 * zwei Tage Rückschau für „gerade gelaufen".
 */
export function packCalendar(entries: AiringEntry[], now = Date.now()): CalendarPayload {
  const all = [...entries].sort((a, b) => {
    if (a.airingAt !== b.airingAt) return a.airingAt - b.airingAt;
    return a.title.localeCompare(b.title, "de");
  });
  const startToday = berlinStartOfDay(now);
  return {
    upcoming: all.filter((e) => e.airingAt >= now - 3 * 3_600_000),
    recent: all.filter((e) => e.airingAt < now && e.airingAt >= startToday - 2 * 86_400_000),
    fetchedAt: now,
  };
}

/** `text()` samt Whitespace-Normalisierung, für Aufrufer die kein Element haben. */
export function normalize(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}

export { text, attr, nilIfEmpty };
