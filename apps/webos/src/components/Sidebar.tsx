// Die Seitenleiste.
//
// Oben links steht nur die Wortmarke „Nori" — kein Symbol daneben. Die fünf
// Einträge sitzen auf Bildmitte, unabhängig von der Marke, die dafür aus dem
// Fluss genommen ist.
//
// Die Leiste klappt nicht auf und schiebt nichts: Sie hat eine feste Breite,
// und der Inhalt beginnt rechts davon. Es gibt damit keinen Zustand, in dem sie
// Inhalt verdeckt.
//
// Für die Navigation ist sie ein eigener Bereich: senkrecht bleibt der Fokus
// in ihr, „rechts" führt zurück auf das zuletzt fokussierte Element im Inhalt,
// und wer sie über „links" betritt, landet auf dem aktiven Eintrag.

import { useLocation, useNavigate } from "react-router-dom";

import { SpotButton } from "../navigation/Spot";
import { Icon, type IconName } from "./Icon";

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
  { to: "/mehr", label: "Mehr", icon: "settings" },
];

export function isTopLevel(pathname: string): boolean {
  return ENTRIES.some((entry) => entry.to === pathname);
}

function isActive(to: string, pathname: string): boolean {
  if (to === "/") return pathname === "/";
  return pathname === to || pathname.startsWith(`${to}/`);
}

export function Sidebar() {
  const location = useLocation();
  const navigate = useNavigate();

  return (
    <aside
      className="sidebar"
      data-focus-group="nav"
      data-focus-lock="vertical"
      data-focus-enter="active"
      data-focus-only-left=""
      data-focus-exit-right="content"
    >
      <div className="brand" aria-label="Nori">Nori</div>
      <nav className="nav-list" aria-label="Hauptnavigation">
        {ENTRIES.map((entry) => {
          const active = isActive(entry.to, location.pathname);
          return (
            <SpotButton
              key={entry.to}
              className={`navbtn${active ? " active" : ""}`}
              focusKey={`nav-${entry.label.toLowerCase()}`}
              aria-current={active ? "page" : undefined}
              onClick={() => {
                if (location.pathname === entry.to) return;
                // Von einer Hauptseite zur nächsten ersetzt der Eintrag den
                // vorherigen: „Zurück" führt dann zur Startseite, nicht durch
                // jede Hauptseite, die man unterwegs angesehen hat.
                const replace = isTopLevel(location.pathname) && location.pathname !== "/";
                navigate(entry.to, { replace: replace && entry.to !== "/" });
              }}
            >
              <Icon name={entry.icon} />
              <span>{entry.label}</span>
            </SpotButton>
          );
        })}
      </nav>
      <div className="remote-hint" aria-hidden="true">
        <strong>Fernbedienung</strong>
        <span>↑ ↓ ← → Navigation</span>
        <span>OK Auswählen</span>
        <span>Zurück Vorherige Ansicht</span>
      </div>
    </aside>
  );
}
