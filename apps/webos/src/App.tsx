// Die Hülle: Anbieter, Routen, Seitenleiste.
//
// `HashRouter`, nicht `BrowserRouter`: das Paket wird von `file://` geladen,
// dort gibt es keinen Server, der Pfade auflöst.

import { Fragment, useCallback, useEffect, type ReactNode } from "react";
import {
  HashRouter, Navigate, Route, Routes, useLocation, useNavigate, useParams,
} from "react-router-dom";

import { Sidebar, isTopLevel } from "./components/Sidebar";
import { BackProvider } from "./navigation/back";
import { ensureFocus } from "./navigation/focusMemory";
import { CalendarPage } from "./pages/Calendar";
import { CatalogPage } from "./pages/Catalog";
import { DetailsPage } from "./pages/Details";
import { HistoryPage } from "./pages/History";
import { HomePage } from "./pages/Home";
import { MorePage } from "./pages/More";
import { ConnectionPage } from "./pages/more/Connection";
import { DataPage } from "./pages/more/Data";
import { DiagnosticsPage } from "./pages/more/Diagnostics";
import { SyncPage } from "./pages/more/Sync";
import { WatchlistPage } from "./pages/Watchlist";
import { PlayerPage } from "./player/PlayerPage";
import { log } from "./services/log";
import { exitApp } from "./services/webos";
import { DataProvider } from "./state/data";
import { LibraryProvider } from "./state/library";
import { SettingsProvider } from "./state/settings";
import { SyncProvider } from "./state/sync";

function Shell() {
  const location = useLocation();
  const navigate = useNavigate();
  const isPlayer = location.pathname.startsWith("/player");

  useEffect(() => {
    log("nav", "Route", location.pathname);
  }, [location.pathname]);

  /**
   * Es darf keinen Zustand geben, in dem nichts fokussiert ist — dann wirkt
   * die Fernbedienung tot. Die Navigation holt verlorenen Fokus sofort zurück;
   * diese Prüfung ist das Netz darunter.
   */
  useEffect(() => {
    const timer = window.setInterval(ensureFocus, 600);
    return () => window.clearInterval(timer);
  }, []);

  /**
   * Was „Zurück" tut, wenn kein Overlay mehr offen ist.
   *
   * Auf der Startseite verlässt es die App. Auf einer anderen Hauptseite geht
   * es zur Startseite — nicht durch jede Hauptseite, die man unterwegs
   * angesehen hat. Überall sonst eine Ansicht zurück.
   */
  const onBackExhausted = useCallback(() => {
    if (location.pathname === "/") {
      log("nav", "Zurück auf der Startseite → App verlassen");
      exitApp();
      return;
    }
    if (isTopLevel(location.pathname) && window.history.length <= 2) {
      navigate("/", { replace: true });
      return;
    }
    navigate(-1);
  }, [location.pathname, navigate]);

  return (
    <BackProvider onExhausted={onBackExhausted}>
      <div className={`app-shell${isPlayer ? " playing" : ""}`}>
        {isPlayer ? null : <Sidebar />}
        <div
          className="app-main"
          data-focus-group="content"
          data-focus-enter="last"
          data-focus-fallback-left="nav"
        >
          <Routes>
            <Route path="/" element={<HomePage />} />
            <Route path="/katalog" element={<CatalogPage />} />
            <Route path="/kalender" element={<CalendarPage />} />
            <Route path="/merkliste" element={<WatchlistPage />} />
            <Route path="/mehr" element={<MorePage />} />
            <Route path="/mehr/verbindung" element={<ConnectionPage />} />
            <Route path="/mehr/abgleich" element={<SyncPage />} />
            <Route path="/mehr/daten" element={<DataPage />} />
            <Route path="/mehr/diagnose" element={<DiagnosticsPage />} />
            <Route path="/mehr/verlauf" element={<HistoryPage />} />
            <Route path="/titel/:provider/:slug" element={<PerTitle><DetailsPage /></PerTitle>} />
            <Route path="/player/:provider/:slug" element={<PerTitle><PlayerPage /></PerTitle>} />
            {/* Adressen der vorherigen Oberfläche, damit gemerkte Einstiege weiter führen. */}
            <Route path="/entdecken" element={<Navigate to="/katalog" replace />} />
            <Route path="/suche" element={<Navigate to="/katalog" replace />} />
            <Route path="/einstellungen" element={<Navigate to="/mehr" replace />} />
            <Route path="/verlauf" element={<Navigate to="/mehr/verlauf" replace />} />
            <Route path="*" element={<HomePage />} />
          </Routes>
        </div>
      </div>
    </BackProvider>
  );
}

/**
 * Zwingt einen Neuaufbau, wenn ein anderer Titel geöffnet wird.
 *
 * React Router tauscht bei gleichem Muster nur die Parameter aus, die
 * Komponente bleibt stehen — und mit ihr ihr Zustand: Staffel 7 von Detektiv
 * Conan hätte sich auf Frieren übertragen. Bewusst **ohne** die Abfrage: im
 * Player wechselt die Folge über `?episode=`, und ein Neuaufbau dabei würde die
 * laufende Wiedergabe abreißen.
 */
function PerTitle({ children }: { children: ReactNode }) {
  const { provider, slug } = useParams<{ provider: string; slug: string }>();
  return <Fragment key={`${provider}|${slug}`}>{children}</Fragment>;
}

export function App() {
  return (
    <SettingsProvider>
      <LibraryProvider>
        <SyncProvider>
          <DataProvider>
            <HashRouter>
              <Shell />
            </HashRouter>
          </DataProvider>
        </SyncProvider>
      </LibraryProvider>
    </SettingsProvider>
  );
}
