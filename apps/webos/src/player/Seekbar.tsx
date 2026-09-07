// Die Fortschrittsleiste.
//
// Drei Bereiche: abgespielt, gepuffert, Rest. Hoch genug, dass sie aus drei
// Metern noch eine Leiste ist und kein Strich. Beim Spulen zeigt sie die
// Zielzeit, nicht die aktuelle — sonst spult man blind.

import { formatClock } from "@nori/core";

export function Seekbar({ position, duration, buffered, scrubbing, target }: {
  position: number;
  duration: number;
  buffered: number;
  scrubbing: boolean;
  target: number;
}) {
  const safeDuration = duration > 0 ? duration : 0;
  const shown = scrubbing ? target : position;
  const pct = (value: number) => (safeDuration > 0 ? Math.min(100, Math.max(0, (value / safeDuration) * 100)) : 0);
  const remaining = Math.max(0, safeDuration - shown);

  return (
    <div className={`timeline ${scrubbing ? "scrubbing" : ""}`}>
      <div
        className="timeline-track"
        role="slider"
        aria-label="Wiedergabeposition"
        aria-valuemin={0}
        aria-valuemax={Math.round(safeDuration)}
        aria-valuenow={Math.round(shown)}
        aria-valuetext={formatClock(shown)}
      >
        <span className="timeline-buffer" style={{ width: `${pct(buffered)}%` }} />
        <span className="timeline-played" style={{ width: `${pct(shown)}%` }} />
        <span className="timeline-knob" style={{ left: `${pct(shown)}%` }} />
      </div>
      <div className="timeline-times">
        <time>{formatClock(shown)}</time>
        <time>−{formatClock(remaining)}</time>
      </div>
    </div>
  );
}
