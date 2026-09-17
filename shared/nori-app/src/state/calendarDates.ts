// Kalendertage als `yyyy-MM-dd` — in Berliner Zeit, wie die Quellen.
//
// AniWorld und Serienstream führen ihre Tage in deutscher Zeit. Ein Fernseher
// mit falsch eingestellter Zeitzone, oder ein Gerät im Urlaub, darf „heute"
// deshalb nicht aus seiner eigenen Uhr ableiten — sonst stünde der Tag kurz
// nach Mitternacht beim falschen Datum.
//
// Gerechnet wird mit UTC-Mittag: dort verschiebt keine Sommerzeit ein Datum.

export const WEEKDAY_SHORT = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"];
const WEEKDAY_LONG = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"];
const MONTHS = [
  "Januar", "Februar", "März", "April", "Mai", "Juni",
  "Juli", "August", "September", "Oktober", "November", "Dezember",
];

function pad(value: number): string {
  return value < 10 ? `0${value}` : String(value);
}

export function dayKeyOf(ms: number): string {
  try {
    const parts = new Intl.DateTimeFormat("de-DE", {
      timeZone: "Europe/Berlin", year: "numeric", month: "2-digit", day: "2-digit",
    }).formatToParts(new Date(ms));
    const find = (type: string) => Number(parts.find((part) => part.type === type)?.value);
    const year = find("year");
    const month = find("month");
    const day = find("day");
    if (year && month && day) return `${year}-${pad(month)}-${pad(day)}`;
  } catch {
    /* Rückfall unten */
  }
  const local = new Date(ms);
  return `${local.getFullYear()}-${pad(local.getMonth() + 1)}-${pad(local.getDate())}`;
}

function toDate(key: string): Date {
  const [year, month, day] = key.split("-").map(Number);
  return new Date(Date.UTC(year, (month || 1) - 1, day || 1, 12));
}

function fromDate(date: Date): string {
  return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}`;
}

export function addDays(key: string, days: number): string {
  const date = toDate(key);
  date.setUTCDate(date.getUTCDate() + days);
  return fromDate(date);
}

/** Montag = 0. */
export function weekdayOf(key: string): number {
  return (toDate(key).getUTCDay() + 6) % 7;
}

export function dayNumber(key: string): number {
  return toDate(key).getUTCDate();
}

/** Die sieben Tage (Montag bis Sonntag) der Woche, in der `key` liegt. */
export function weekOf(key: string): string[] {
  const monday = addDays(key, -weekdayOf(key));
  return Array.from({ length: 7 }, (_, index) => addDays(monday, index));
}

export function sameMonth(a: string, b: string): boolean {
  return a.slice(0, 7) === b.slice(0, 7);
}

export function addMonths(key: string, months: number): string {
  const date = toDate(key);
  date.setUTCDate(1);
  date.setUTCMonth(date.getUTCMonth() + months);
  return fromDate(date);
}

/** Sechs volle Wochen ab dem Montag vor dem Monatsersten. */
export function monthGrid(key: string): string[] {
  const first = `${key.slice(0, 7)}-01`;
  const start = addDays(first, -weekdayOf(first));
  return Array.from({ length: 42 }, (_, index) => addDays(start, index));
}

export function longDayLabel(key: string): string {
  const date = toDate(key);
  return `${WEEKDAY_LONG[weekdayOf(key)]}, ${date.getUTCDate()}. ${MONTHS[date.getUTCMonth()]}`;
}

export function monthLabel(key: string): string {
  const date = toDate(key);
  return `${MONTHS[date.getUTCMonth()]} ${date.getUTCFullYear()}`;
}
