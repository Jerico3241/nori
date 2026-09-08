// Die Hülle: Anbieter, Routen, Seitenleiste.
//
// `HashRouter`, nicht `BrowserRouter`: das Paket wird von `file://` geladen,
// dort gibt es keinen Server, der Pfade auflöst. Ein Pfad ohne Raute wäre nach
// dem ersten Neuladen eine 404.

import { useCallback, useEffect } from "react";
import { HashRouter, Route, Routes, useLocation, useNavigate } from "react-router-dom";

import { Sidebar } from "./components/Sidebar";
import { BackProvider } from "./navigation/back";
import { ensureFocus } from "./navigation/focusMemory";
import { CalendarPage } from "./pages/Calendar";
import { DetailsPage } from "./pages/Details";
import { ExplorePage } from "./pages/Explore";
import { HistoryPage } from "./pages/History";
import { HomePage } from "./pages/Home";
import { SearchPage } from "./pages/Search";
import { SettingsPage } from "./pages/Settings";
import { WatchlistPage } from "./pages/Watchlist";
import { PlayerPage } from "./player/PlayerPage";
import { log } from "./services/log";
import { exitApp } from "./services/webos";
import { DataProvider } from "./state/data";
import { LibraryProvider } from "./state/library";
import { SettingsProvider } from "./state/settings";

function Shell() {
  const location = useLocation();
  const navigate = useNavigate();
  const isPlayer = location.pathname.startsWith("/player");

  useEffect(() => {
    log("nav", "Route", location.pathname);
  }, [location.pathname]);

  // Es darf keinen Zustand geben, in dem nichts fokussiert ist — dann wirkt
  // die Fernbedienung tot. Nach jedem Routenwechsel wird das geprüft.
  useEffect(() => {
    const timer = window.setTimeout(ensureFocus, 220);
    return () => window.clearTimeout(timer);
  }, [location.pathname]);

  const onBackExhausted = useCallback(() => {
    if (location.pathname === "/") {
      log("nav", "Zurück auf der Startseite → App verlassen");
      exitApp();
      return;
    }
    navigate(-1);
  }, [location.pathname, navigate]);

  return (
    <BackProvider onExhausted={onBackExhausted}>
      <div className={`app-shell ${isPlayer ? "playing" : ""}`}>
        {isPlayer ? null : <Sidebar />}
        <main className="app-main">
          <Routes>
            <Route path="/" element={<HomePage />} />
            <Route path="/entdecken" element={<ExplorePage />} />
            <Route path="/kalender" element={<CalendarPage />} />
            <Route path="/suche" element={<SearchPage />} />
            <Route path="/merkliste" element={<WatchlistPage />} />
            <Route path="/verlauf" element={<HistoryPage />} />
            <Route path="/einstellungen" element={<SettingsPage />} />
            <Route path="/titel/:provider/:slug" element={<DetailsPage />} />
            <Route path="/player/:provider/:slug" element={<PlayerPage />} />
            <Route path="*" element={<HomePage />} />
          </Routes>
        </main>
      </div>
    </BackProvider>
  );
}

export function App() {
  return (
    <SettingsProvider>
      <LibraryProvider>
        <DataProvider>
          <HashRouter>
            <Shell />
          </HashRouter>
        </DataProvider>
      </LibraryProvider>
    </SettingsProvider>
  );
}
