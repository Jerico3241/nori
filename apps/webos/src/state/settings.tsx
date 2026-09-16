// Geräteeinstellungen des webOS-Clients.
//
// Getrennt von der Bibliothek: Sprache, Hoster, Resume und Autoplay gehören
// zum gemeinsamen Nori-Datenmodell und liegen deshalb in `library.tsx`. Hier
// steht nur, was den Fernseher selbst betrifft — wohin er sich verbindet und
// wie er den Player bedient.

import {
  createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode,
} from "react";
import type { TransportMode } from "../services/gateway";
import type { TmdbMode } from "../services/tmdb";
import { warn } from "../services/log";
import { setPerformanceSetting, type PerformanceSetting } from "../services/performance";

const STORAGE_KEY = "nori.webos.settings";

export interface DeviceSettings {
  transport: TransportMode;
  serverUrl: string;
  /** Sekunden bis die Bedienung im Player ausblendet. */
  controlsTimeout: number;
  /** Sekunden je Sprung mit Links/Rechts. */
  seekStep: number;
  /** Sekunden Countdown vor der nächsten Folge. */
  autoplayCountdown: number;
  /**
   * Woher die TMDB-Daten kommen.
   *
   *   „server"  — der Nori-Server hält den Schlüssel. Der empfohlene Weg: ein
   *               Schlüssel statt einer je Gerät, ein Zwischenspeicher für
   *               alle Fernseher, eine Ratenbegrenzung statt mehrerer.
   *   „direct"  — dieser Fernseher fragt TMDB selbst. Ohne eingetragenen
   *               Schlüssel mit dem mitgelieferten; einzurichten ist also
   *               nichts.
   *   „aus"     — keine TMDB-Daten. Ein gültiger Zustand: Nori zeigt dann die
   *               Cover und Texte der Quellen. Nur, wenn jemand es wählt.
   */
  tmdbMode: TmdbMode;
  /**
   * Ein **eigener** Schlüssel für den direkten Weg. Leer heißt: der
   * mitgelieferte aus dem Kern (`BUILT_IN_TMDB_KEY`) — nicht „kein TMDB".
   */
  tmdbKey: string;
  /** Weiche Flächen kosten auf älteren Panels Bilder pro Sekunde. */
  reduceEffects: boolean;
  /**
   * Wie sparsam Nori zeichnet und nachlädt.
   *
   *   „auto"  — Nori misst und entscheidet: ein kurzer Rechenlauf beim ersten
   *             Start und danach die tatsächliche Fokuslatenz.
   *   „full"  — immer die volle Darstellung.
   *   „lean"  — immer sparsam, auch wenn das Gerät schnell genug wäre.
   *
   * Getrennt von `reduceEffects`: „Animationen reduzieren" ist eine Frage des
   * Geschmacks und der Barrierefreiheit, der Leistungsmodus eine der Hardware.
   * Wer Übergänge mag, aber ein schwaches Panel hat, soll beides einzeln
   * einstellen können.
   */
  performance: PerformanceSetting;
  debug: boolean;
}

const DEFAULTS: DeviceSettings = {
  transport: "server",
  serverUrl: "",
  controlsTimeout: 4,
  seekStep: 10,
  autoplayCountdown: 10,
  tmdbMode: "server",
  tmdbKey: "",
  reduceEffects: false,
  performance: "auto",
  debug: false,
};

interface SettingsContextValue {
  settings: DeviceSettings;
  update(patch: Partial<DeviceSettings>): void;
  reset(): void;
}

const SettingsContext = createContext<SettingsContextValue | null>(null);

/** Der abgelegte Stand. Auch `main.tsx` liest ihn — vor dem ersten Zeichnen. */
export function readSettings(): DeviceSettings {
  return read();
}

function read(): DeviceSettings {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULTS;
    const parsed = JSON.parse(raw) as Partial<DeviceSettings>;
    const merged = { ...DEFAULTS, ...parsed };
    // Ein Stand von vor dem Serverweg kennt `tmdbMode` nicht. Wer dort einen
    // eigenen Schlüssel eingetragen hat, meinte damit „dieser Fernseher" — die
    // Voreinstellung „server" würde ihn stillschweigend übergehen.
    if (parsed.tmdbMode === undefined) {
      merged.tmdbMode = (parsed.tmdbKey ?? "").trim() ? "direct" : DEFAULTS.tmdbMode;
    }
    // Ein Stand von vor dem Leistungsmodus kennt nur „Animationen reduzieren".
    // Wer den eingeschaltet hatte, hat ein Gerät, dem etwas fehlt — die
    // Messung darf das bestätigen, aber nicht dahinter zurückfallen.
    if (parsed.performance === undefined) merged.performance = DEFAULTS.performance;
    return merged;
  } catch (cause) {
    warn("app", "Einstellungen nicht lesbar", cause);
    return DEFAULTS;
  }
}

export function SettingsProvider({ children }: { children: ReactNode }) {
  const [settings, setSettings] = useState<DeviceSettings>(read);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
    } catch (cause) {
      warn("app", "Einstellungen nicht speicherbar", cause);
    }
    localStorage.setItem("nori.debug", settings.debug ? "1" : "0");
    document.documentElement.dataset.effects = settings.reduceEffects ? "reduced" : "full";
    setPerformanceSetting(settings.performance);
  }, [settings]);

  const update = useCallback((patch: Partial<DeviceSettings>) => {
    setSettings((current) => ({ ...current, ...patch }));
  }, []);

  const reset = useCallback(() => setSettings(DEFAULTS), []);

  const value = useMemo(() => ({ settings, update, reset }), [settings, update, reset]);
  return <SettingsContext.Provider value={value}>{children}</SettingsContext.Provider>;
}

export function useSettings(): SettingsContextValue {
  const ctx = useContext(SettingsContext);
  if (!ctx) throw new Error("useSettings außerhalb von SettingsProvider");
  return ctx;
}
