// Die Hülle: Anbieter, Seitenleiste, Routen, Tastatur.
//
// `HashRouter`, nicht `BrowserRouter`: die Oberfläche wird im Paket von
// `file://` geladen, und dort gibt es keinen Server, der Pfade auflöst.
//
// Die Seitenleiste ist links und bleibt es — auf einem Fenster ist sie
// Orientierung und Ziel zugleich. Im Player verschwindet sie; dort gibt es nur
// einen Inhalt, und der ist das Bild.

import { Icon, useSettings, type IconName } from "@nori/app";
import { Fragment, useEffect, type ReactNode } from "react";
import {
  HashRouter, Navigate, Route, Routes, useLocation, useNavigate, useParams,
} from "react-router-dom";

import {
  DataProvider, LibraryProvider, SettingsProvider,
} from "@nori/app";
import { bridge } from "./bridge";
import { WINDOWS_DEFAULTS } from "./platform";
import { CatalogSearchField, CatalogPage } from "./pages/Catalog";
import { DetailsPage } from "./pages/Details";
import { HomePage } from "./pages/Home";
import { CalendarPage, HistoryPage, WatchlistPage } from "./pages/Library";
import { SettingsPage } from "./pages/Settings";
import { PlayerPage } from "./player/PlayerPage";
import { SyncProvider } from "./state/sync";

interface Entry {
  to: string;
  label: string;
  icon: IconName;
}

const ENTRIES: Entry[] = [
  { to: "/", label: "Start", icon: "home" },
  { to: "/katalog", label: "Katalog", icon: "grid" },
  { to: "/kalender", label: "Kalender", icon: "calendar" },
  { to: "/merkliste", label: "Merkliste", icon: "heart" },
  { to: "/verlauf", label: "Verlauf", icon: "history" },
  { to: "/einstellungen", label: "Einstellungen", icon: "settings" },
];

function isActive(to: string, path: string): boolean {
  return to === "/" ? path === "/" : path.startsWith(to);
}

function Sidebar() {
  const location = useLocation();
  const navigate = useNavigate();
  return (
    <aside className="sidebar">
      <div className="brand">
        <img src="./icon.png" alt="" />
        Nori
      </div>
      <nav className="nav" aria-label="Hauptnavigation">
        {ENTRIES.map((entry) => {
          const active = isActive(entry.to, location.pathname);
          return (
            <button
              key={entry.to}
              type="button"
              className={`navbtn${active ? " active" : ""}`}
              aria-current={active ? "page" : undefined}
              title={entry.label}
              onClick={() => navigate(entry.to)}
            >
              <Icon name={entry.icon} />
              <span>{entry.label}</span>
            </button>
          );
        })}
      </nav>
      <div className="sidebar-foot">Nori {__NORI_APP_VERSION__}</div>
    </aside>
  );
}

/** Kopfzeile: Zurück/Vor, Titel, Suche. */
function TopBar() {
  const location = useLocation();
  const navigate = useNavigate();
  const entry = ENTRIES.find((item) => isActive(item.to, location.pathname));
  const onDetails = location.pathname.startsWith("/titel/");
  return (
    <header className="topbar">
      <div className="navbuttons">
        <button
          type="button"
          className="btn ghost icon-only"
          aria-label="Zurück"
          title="Zurück (Alt + ←)"
          onClick={() => navigate(-1)}
        >
          <Icon name="back" />
        </button>
        <button
          type="button"
          className="btn ghost icon-only"
          aria-label="Vorwärts"
          title="Vorwärts (Alt + →)"
          onClick={() => navigate(1)}
        >
          <Icon name="chevronRight" />
        </button>
      </div>
      <h1>
        {entry ? entry.label : onDetails ? "Titel" : "Nori"}
      </h1>
      <div className="topbar-actions">
        <CatalogSearchField />
      </div>
    </header>
  );
}

/**
 * Tastenkürzel, die überall gelten.
 *
 * Bewusst wenige und bewusst die, die auf Windows überall dasselbe tun:
 * Alt + Pfeil für den Verlauf, F11 für Vollbild, Strg + F für die Suche,
 * Escape zurück. Der Player bringt seine eigenen mit.
 */
function Shortcuts() {
  const navigate = useNavigate();
  const location = useLocation();
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const inField = event.target instanceof HTMLInputElement
        || event.target instanceof HTMLTextAreaElement
        || event.target instanceof HTMLSelectElement;
      if (event.key === "F11") {
        event.preventDefault();
        void window.nori?.window.toggleFullscreen();
        return;
      }
      if (event.altKey && event.key === "ArrowLeft") {
        event.preventDefault();
        navigate(-1);
        return;
      }
      if (event.altKey && event.key === "ArrowRight") {
        event.preventDefault();
        navigate(1);
        return;
      }
      if ((event.ctrlKey || event.metaKey) && (event.key === "f" || event.key === "k")) {
        event.preventDefault();
        document.querySelector<HTMLInputElement>(".search input")?.focus();
        return;
      }
      if (event.key === "Escape" && !inField && location.pathname !== "/") {
        event.preventDefault();
        navigate(-1);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [navigate, location.pathname]);
  return null;
}

function Shell() {
  const location = useLocation();
  const isPlayer = location.pathname.startsWith("/player");
  const main = useScrollReset(location.pathname);

  return (
    <div className={`shell${isPlayer ? " playing" : ""}`}>
      <Shortcuts />
      {isPlayer ? null : <Sidebar />}
      <div className="main" ref={main}>
        {isPlayer ? null : <TopBar />}
        <Routes>
          <Route path="/" element={<HomePage />} />
          <Route path="/katalog" element={<CatalogPage />} />
          <Route path="/kalender" element={<CalendarPage />} />
          <Route path="/merkliste" element={<WatchlistPage />} />
          <Route path="/verlauf" element={<HistoryPage />} />
          <Route path="/einstellungen" element={<SettingsPage />} />
          <Route path="/titel/:provider/:slug" element={<PerTitle><DetailsPage /></PerTitle>} />
          <Route path="/player/:provider/:slug" element={<PerTitle><PlayerPage /></PerTitle>} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </div>
    </div>
  );
}

/**
 * Bei jedem Seitenwechsel wieder nach oben.
 *
 * Ohne das steht eine frisch geöffnete Detailseite mittendrin — der
 * Scrollbereich ist derselbe, und der Browser merkt sich seine Position.
 */
function useScrollReset(pathname: string) {
  const ref = { current: null as HTMLDivElement | null };
  useEffect(() => {
    document.querySelector(".main")?.scrollTo({ top: 0 });
  }, [pathname]);
  return (node: HTMLDivElement | null) => {
    ref.current = node;
  };
}

/**
 * Zwingt einen Neuaufbau, wenn ein anderer Titel geöffnet wird.
 *
 * React Router tauscht bei gleichem Muster nur die Parameter aus, die
 * Komponente bleibt stehen — und mit ihr ihr Zustand. Bewusst **ohne** die
 * Abfrage: im Player wechselt die Folge über `?episode=`, und ein Neuaufbau
 * dabei risse die laufende Wiedergabe ab.
 */
function PerTitle({ children }: { children: ReactNode }) {
  const { provider, slug } = useParams<{ provider: string; slug: string }>();
  return <Fragment key={`${provider}|${slug}`}>{children}</Fragment>;
}

/** Hält `data-effects` am Wurzelelement aktuell. */
function Effects() {
  const { settings } = useSettings();
  useEffect(() => {
    document.documentElement.dataset.effects = settings.reduceEffects ? "reduced" : "full";
  }, [settings.reduceEffects]);
  return null;
}

/**
 * Sagt dem Hauptprozess, welchen Weg die Daten nehmen sollen.
 *
 * Die Einstellungen liegen im Fenster, die Quellenschicht im Hauptprozess —
 * einer von beiden muss es dem anderen sagen. Beim Start tut das `main.tsx`,
 * vor dem ersten Rendern; hier geht es nur noch um spätere Änderungen.
 *
 * Steht **über** `DataProvider`, damit die Meldung draußen ist, bevor der
 * Wechsel dort die geladenen Listen verwirft und neu holt.
 */
function Transport({ children }: { children: ReactNode }) {
  const { settings } = useSettings();
  useEffect(() => {
    const api = bridge();
    if (api) void api.gateway.configure(settings.transport, settings.serverUrl);
  }, [settings.transport, settings.serverUrl]);
  return <>{children}</>;
}

export function App() {
  return (
    <SettingsProvider defaults={WINDOWS_DEFAULTS}>
      <LibraryProvider>
        <SyncProvider>
          <Transport>
            <DataProvider>
              <Effects />
              <HashRouter>
                <Shell />
              </HashRouter>
            </DataProvider>
          </Transport>
        </SyncProvider>
      </LibraryProvider>
    </SettingsProvider>
  );
}
