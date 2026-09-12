// Die Hülle: Anbieter, Routen, Seitenleiste.
//
// `HashRouter`, nicht `BrowserRouter`: das Paket wird von `file://` geladen,
// dort gibt es keinen Server, der Pfade auflöst. Ein Pfad ohne Raute wäre nach
// dem ersten Neuladen eine 404.

import { Fragment, useCallback, useEffect, type ReactNode } from "react";
import { HashRouter, Route, Routes, useLocation, useNavigate, useParams } from "react-router-dom";

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

  /**
   * Und danach weiter, alle 600 ms.
   *
   * Ein Routenwechsel ist nicht der einzige Weg, den Fokus zu verlieren: Jede
   * Reihe, die verschwindet, weil ein Abruf scheitert, und jede Liste, die
   * durch eine neue ersetzt wird, nimmt das fokussierte Element mit aus dem
   * Dokument. Danach steht der Fokus auf `body`, und der Fernseher reagiert auf
   * keine Taste mehr — genau dieser Zustand trat auf, als der Katalogabruf
   * mitten im Betrieb wegfiel.
   *
   * Die Prüfung kostet einen Blick auf ein Element, solange einer fokussiert
   * ist; nur wenn keiner es ist, wird gesucht. Im Player mit ausgeblendeter
   * Bedienung findet sie nichts Sichtbares und tut nichts — dort hören
   * ohnehin die Tastengriffe am Fenster zu.
   */
  useEffect(() => {
    const timer = window.setInterval(ensureFocus, 600);
    return () => window.clearInterval(timer);
  }, []);

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
            <Route path="/titel/:provider/:slug" element={<PerTitle><DetailsPage /></PerTitle>} />
            <Route path="/player/:provider/:slug" element={<PerTitle><PlayerPage /></PerTitle>} />
            <Route path="*" element={<HomePage />} />
          </Routes>
        </main>
      </div>
    </BackProvider>
  );
}

/**
 * Zwingt einen Neuaufbau, wenn ein anderer Titel geöffnet wird.
 *
 * React Router tauscht bei gleichem Muster nur die Parameter aus, die
 * Komponente bleibt stehen — und mit ihr ihr Zustand. Auf der Detailseite hieß
 * das: Wer bei Detektiv Conan Staffel 7 wählt und danach Frieren öffnet,
 * bekommt Frieren **Staffel 7** zu sehen, samt Folgen, die es dort nicht gibt.
 * Dasselbe galt für Bilder, Bewertung und ähnliche Titel.
 *
 * Ein Rücksetzen im Effekt ginge auch, würde aber ein Bild lang den alten
 * Stand zeigen — und bei jedem neuen Zustandsfeld die Frage aufwerfen, ob es
 * dort mitgenommen wurde. Der Schlüssel erledigt das für alle auf einmal.
 *
 * Bewusst **ohne** die Abfrage: Im Player wechselt die Folge über
 * `?episode=`, und ein Neuaufbau dabei würde die laufende Wiedergabe abreißen.
 */
function PerTitle({ children }: { children: ReactNode }) {
  const { provider, slug } = useParams<{ provider: string; slug: string }>();
  return <Fragment key={`${provider}|${slug}`}>{children}</Fragment>;
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
