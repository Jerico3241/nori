// Die Bewertung, wie sie auch auf iPhone und Mac steht.
//
// Ein Stern und eine Zahl, kein Balken und keine fünf gefüllten Sterne: Auf
// drei Metern zählt die Zahl, und fünf Symbole nebeneinander werden bei dieser
// Größe zu einem Fleck.
//
// Der warme Ton ist die **einzige** Stelle, an der Nori einen benutzt — er
// kommt aus `NoriTheme.star` und gehört zur Bewertung, nicht zur App.

import type { ReactNode } from "react";

import { ratingText } from "@nori/app";

export interface RatingProps {
  /** TMDBs Zehnerskala. */
  value: number | null;
  /** Stimmenzahl. Ohne Grundlage wird die Bewertung nicht gezeigt. */
  votes?: number | null;
  /**
   * Ab wie vielen Stimmen die Bewertung etwas heißt.
   *
   * Fünfzig, wie in `HomeRanking`: ein Titel mit 10,0 aus zwei Stimmen ist
   * keine Auskunft, sondern eine Zufallszahl. Eine Kachel, die sie trotzdem
   * zeigt, behauptet mehr, als sie weiß.
   */
  minimumVotes?: number;
  className?: string;
}

// `ratingText` liegt in `@nori/app`: die Regel, ab wann eine Bewertung etwas
// heißt, gilt für jede Nori-Oberfläche, die Darstellung nur für diese.
export { ratingText };

export function Rating({ value, votes, minimumVotes = 50, className }: RatingProps): ReactNode {
  if (value === null || value <= 0) return null;
  if (votes !== undefined && votes !== null && votes < minimumVotes) return null;

  return (
    <span className={`rating ${className ?? ""}`} aria-label={`Bewertung ${value.toFixed(1)} von 10`}>
      <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false" className="rating-star">
        <path
          fill="currentColor"
          d="M12 2.6l2.9 5.9 6.5.9-4.7 4.6 1.1 6.5L12 17.4l-5.8 3.1 1.1-6.5L2.6 9.4l6.5-.9z"
        />
      </svg>
      {value.toFixed(1).replace(".", ",")}
    </span>
  );
}
