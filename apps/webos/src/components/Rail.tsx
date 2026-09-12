// Eine horizontale Reihe.
//
// Der eigene Container je Reihe ist der Grund, warum der Fokus beim Zurückgehen
// wieder auf derselben Kachel steht: Spotlight merkt sich das zuletzt
// fokussierte Kind je Container („enterTo: last-focused"), und Nori merkt sich
// zusätzlich den Schlüssel, damit es auch einen Neuaufbau der Seite übersteht.

import type { ReactNode } from "react";
import { SpotArea } from "../navigation/Spot";

export function Rail({ title, count, note, children, id }: {
  title: string;
  count?: number;
  /**
   * Eine Zeile, die die Überschrift begründet.
   *
   * Nur dort, wo sie etwas erklärt — „Aus deinem Verlauf" unter „Für dich",
   * „Reihenfolge der Quelle" unter „Neu im Katalog". Eine Reihe, die ihren
   * Namen von selbst erklärt, bekommt keine.
   */
  note?: string;
  id: string;
  children: ReactNode;
}) {
  return (
    /*
      `data-rail` und nicht `id`: `spotlightId` wandert zu Spotlight, nicht in
      das `id`-Attribut. Ein Test, der `#rail-continue` sucht, findet deshalb
      nichts — und das ist ihm einmal passiert.
    */
    <section className="rail" data-rail={id} aria-label={title}>
      <header>
        <h2>{title}</h2>
        {typeof count === "number" && count > 0 ? <span className="rail-count">{count}</span> : null}
        {note ? <span className="rail-note">{note}</span> : null}
      </header>
      <SpotArea className="rail-track" spotlightId={`rail-${id}`}>
        {children}
      </SpotArea>
    </section>
  );
}
