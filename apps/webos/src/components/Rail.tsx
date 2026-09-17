// Eine waagerechte Reihe mit Überschrift.
//
// Zwei Markierungen, auf die sich die Navigation stützt:
//
// - `data-reveal` am Abschnitt: wer in die Reihe wechselt, sieht ihre
//   Überschrift mit — „Neu & beliebt" verschwindet nicht über dem Bildrand,
//   während nur noch das Poster darunter steht.
// - `data-scroll-x` an der Spur: sie wird beim Weiterdrücken genau so weit
//   bewegt, dass die nächste Karte ganz dasteht, samt Fokusring.
//
// `data-rail` statt `id`, damit Tests und Protokoll die Reihe finden.

import type { ReactNode } from "react";

export function Rail({ id, title, note, children }: {
  id: string;
  title: string;
  /** Eine Zeile, die die Überschrift begründet — nur wo sie etwas erklärt. */
  note?: string;
  children: ReactNode;
}) {
  return (
    <section className="section rail-section" data-reveal="" data-rail={id} aria-label={title}>
      <div className="section-head">
        <h2>{title}</h2>
        {note ? <span>{note}</span> : null}
      </div>
      <div className="rail" data-scroll-x="" data-scroll-key={`rail-${id}`}>
        <div className="rail-inner" data-nav-row="">{children}</div>
      </div>
    </section>
  );
}
