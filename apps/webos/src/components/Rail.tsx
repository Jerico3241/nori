// Eine horizontale Reihe.
//
// Der eigene Container je Reihe ist der Grund, warum der Fokus beim Zurückgehen
// wieder auf derselben Kachel steht: Spotlight merkt sich das zuletzt
// fokussierte Kind je Container („enterTo: last-focused"), und Nori merkt sich
// zusätzlich den Schlüssel, damit es auch einen Neuaufbau der Seite übersteht.

import type { ReactNode } from "react";
import { SpotArea } from "../navigation/Spot";

export function Rail({ title, count, children, id }: {
  title: string;
  count?: number;
  id: string;
  children: ReactNode;
}) {
  return (
    <section className="rail" aria-label={title}>
      <header>
        <h2>{title}</h2>
        {typeof count === "number" && count > 0 ? <span className="rail-count">{count}</span> : null}
      </header>
      <SpotArea className="rail-track" spotlightId={id}>
        {children}
      </SpotArea>
    </section>
  );
}
