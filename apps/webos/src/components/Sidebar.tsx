// Die Seitenleiste.
//
// Schmal im Normalzustand, breiter sobald sie den Fokus hat — und nur dann.
// Ein Ausklappen beim Vorbeifahren mit dem Fokus in der Reihe daneben würde
// bei jeder Bewegung das halbe Bild verschieben.

import { useCallback, useState } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import { SpotArea, SpotButton } from "../navigation/Spot";
import { Icon, type IconName } from "./Icon";

interface Entry {
  to: string;
  label: string;
  icon: IconName;
}

const ENTRIES: Entry[] = [
  { to: "/", label: "Start", icon: "home" },
  { to: "/entdecken", label: "Entdecken", icon: "compass" },
  { to: "/kalender", label: "Kalender", icon: "calendar" },
  { to: "/suche", label: "Suche", icon: "search" },
  { to: "/merkliste", label: "Merkliste", icon: "bookmark" },
  { to: "/verlauf", label: "Verlauf", icon: "history" },
  { to: "/einstellungen", label: "Einstellungen", icon: "settings" },
];

export function Sidebar() {
  const location = useLocation();
  const navigate = useNavigate();
  const [expanded, setExpanded] = useState(false);

  const active = useCallback(
    (to: string) => (to === "/" ? location.pathname === "/" : location.pathname.startsWith(to)),
    [location.pathname],
  );

  return (
    <SpotArea
      className={`side-nav ${expanded ? "expanded" : ""}`}
      spotlightId="sidebar"
      onFocus={() => setExpanded(true)}
      onBlur={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget as Node)) setExpanded(false);
      }}
    >
      <div className="brand" aria-label="Nori">
        <span className="brand-mark">N</span>
        <span className="brand-word">Nori</span>
      </div>
      <nav className="nav-links">
        {ENTRIES.map((entry) => (
          <SpotButton
            key={entry.to}
            className={`nav-link ${active(entry.to) ? "active" : ""}`}
            focusRoute="shell"
            focusArea="sidebar"
            focusKey={entry.to}
            aria-current={active(entry.to) ? "page" : undefined}
            onClick={() => navigate(entry.to)}
          >
            <Icon name={entry.icon} />
            <span className="nav-label">{entry.label}</span>
          </SpotButton>
        ))}
      </nav>
    </SpotArea>
  );
}
