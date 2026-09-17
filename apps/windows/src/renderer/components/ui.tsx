// Die Bausteine der Desktop-Oberfläche.
//
// ## Warum nicht dieselben wie auf dem Fernseher
//
// Die Logik teilen sich beide Apps vollständig (`@nori/app`) — welches Bild
// eine Kachel zeigt, in welcher Größe, wann es geladen wird, was in der Zeile
// darunter steht. Was sich unterscheidet, ist die **Bedienung**, und das ist
// kein Detail:
//
//     Fernseher     ein Fokus, der sich mit vier Tasten bewegt. Jede Kachel
//                   ist ein `SpotButton`, die Navigation rechnet Geometrie,
//                   der Fokus wächst um sieben Prozent, damit man ihn aus drei
//                   Metern sieht.
//
//     Schreibtisch  ein Zeiger, der überall sein kann, und eine Tastatur, die
//                   der Reihe nach durchgeht. Kein Fokusmodell, sondern
//                   `:hover`, `:active` und `:focus-visible` — drei Zustände,
//                   die der Browser selbst kennt.
//
// Die TV-Navigation hierher zu kopieren wäre der Fehler, den man Apps ansieht,
// die von einem Fernseher kommen: ein Zeiger, der an unsichtbaren Rastern
// hängen bleibt, und eine Tabulatortaste, die nicht tut, was sie überall sonst
// tut.

import { Artwork, Icon, type ArtworkKind, type IconName } from "@nori/app";
import type { CatalogProvider } from "@nori/core";
import {
  memo, useCallback, useEffect, useRef, useState, type ReactNode,
} from "react";

// ---------------------------------------------------------------------------
// Reihe

/**
 * Eine waagerechte Reihe.
 *
 * Auf dem Schreibtisch gibt es drei Wege, sie zu bewegen, und alle drei müssen
 * gehen: das Rad (waagerecht oder senkrecht über der Reihe), die beiden
 * Knöpfe, die beim Überfahren erscheinen, und die Tastatur, sobald der Fokus
 * in der Reihe steht. Auf einem Fernseher gäbe es nur den letzten.
 */
export function Rail({ title, note, children, action }: {
  title: string;
  note?: string;
  action?: ReactNode;
  children: ReactNode;
}) {
  const track = useRef<HTMLDivElement>(null);
  const [edges, setEdges] = useState({ start: true, end: true });

  const measure = useCallback(() => {
    const node = track.current;
    if (!node) return;
    setEdges({
      start: node.scrollLeft <= 4,
      end: node.scrollLeft + node.clientWidth >= node.scrollWidth - 4,
    });
  }, []);

  useEffect(() => {
    measure();
    const node = track.current;
    if (!node) return undefined;
    // `ResizeObserver` statt eines Fensterereignisses: die Reihe ändert ihre
    // Breite auch, wenn nur die Seitenleiste umschaltet.
    const observer = new ResizeObserver(measure);
    observer.observe(node);
    return () => observer.disconnect();
  }, [measure, children]);

  const step = (direction: -1 | 1) => {
    const node = track.current;
    if (!node) return;
    // Eine knappe Sichtbreite: so bleibt immer eine Karte als Anker stehen.
    node.scrollBy({ left: direction * Math.max(240, node.clientWidth * 0.82), behavior: "smooth" });
  };

  /**
   * Das Rad bewegt die Reihe, aber nur wenn sie sich bewegen lässt.
   *
   * Ein Rad, das über einer Reihe die Seite nicht mehr scrollt, ist ein
   * bekanntes Ärgernis. Deshalb: am Ende der Reihe wird das Ereignis nicht
   * mehr angenommen, und die Seite scrollt weiter wie immer.
   */
  const onWheel = (event: React.WheelEvent<HTMLDivElement>) => {
    const node = track.current;
    if (!node || event.deltaX !== 0) return;
    const delta = event.deltaY;
    const atStart = node.scrollLeft <= 0 && delta < 0;
    const atEnd = node.scrollLeft + node.clientWidth >= node.scrollWidth - 1 && delta > 0;
    if (atStart || atEnd) return;
    event.preventDefault();
    node.scrollLeft += delta;
  };

  return (
    <section className="section">
      <div className="section-head">
        <h2>{title}</h2>
        {note ? <span>{note}</span> : null}
        {action}
      </div>
      <div className="rail-wrap">
        <button
          type="button"
          className="rail-nav left"
          aria-label="Weiter nach links"
          disabled={edges.start}
          onClick={() => step(-1)}
        >
          <Icon name="back" />
        </button>
        <div className="rail" ref={track} onScroll={measure} onWheel={onWheel}>
          {children}
        </div>
        <button
          type="button"
          className="rail-nav right"
          aria-label="Weiter nach rechts"
          disabled={edges.end}
          onClick={() => step(1)}
        >
          <Icon name="chevronRight" />
        </button>
      </div>
    </section>
  );
}

// ---------------------------------------------------------------------------
// Karten

export interface CardProps {
  slug: string;
  provider: CatalogProvider;
  title: string;
  alts?: string[];
  subtitle?: string | null;
  percent?: number;
  eager?: boolean;
  onSelect(): void;
}

function clampPercent(value?: number): number {
  return Math.max(0, Math.min(100, Math.round(value ?? 0)));
}

/**
 * Die Kachel einer Serie: 2:3-Poster, Titel, eine Zeile darunter.
 *
 * `memo` mit Wertvergleich, nicht aus Prinzip: Im Katalog stehen bis zu
 * sechzig davon, und jeder eintreffende TMDB-Treffer baut die Kandidatenliste
 * neu — mit neuen Objekten, aber denselben Angaben.
 */
export const PosterCard = memo(function PosterCard(props: CardProps) {
  const percent = clampPercent(props.percent);
  return (
    <button
      type="button"
      className="card poster"
      onClick={props.onSelect}
      title={props.title}
      aria-label={`${props.title}${props.subtitle ? `, ${props.subtitle}` : ""}`}
    >
      <span className="card-art poster-art" data-nav-quiet="">
        <Artwork
          kind="poster"
          slug={props.slug}
          provider={props.provider}
          title={props.title}
          alts={props.alts}
          eager={props.eager}
        />
        {percent > 0 ? (
          <span className="card-progress" aria-hidden="true"><i style={{ width: `${percent}%` }} /></span>
        ) : null}
        <span className="card-play" aria-hidden="true"><Icon name="play" /></span>
      </span>
      <span className="card-title">{props.title}</span>
      {props.subtitle ? <span className="card-sub">{props.subtitle}</span> : null}
    </button>
  );
}, sameCard);

/** Eine 16:9-Karte — für Folgen, nicht für Serien. */
export const LandscapeCard = memo(function LandscapeCard(
  props: CardProps & {
    still?: string | null;
    /**
     * „Aus Weiterschauen entfernen". Ein eigener Knopf auf der Karte statt
     * eines Kontextmenüs; er erscheint beim Überfahren und ist mit der
     * Tastatur erreichbar. Gelöscht wird dabei nichts (`WatchMarks` im Kern).
     */
    onRemove?(): void;
  },
) {
  const percent = clampPercent(props.percent);
  return (
    <div className="card-wrap">
    <button
      type="button"
      className="card land"
      onClick={props.onSelect}
      title={props.title}
      aria-label={`${props.title}${props.subtitle ? `, ${props.subtitle}` : ""}`}
    >
      <span className="card-art land-art" data-nav-quiet="">
        <Artwork
          kind={props.still ? "still" : "backdrop"}
          src={props.still}
          slug={props.slug}
          provider={props.provider}
          title={props.title}
          alts={props.alts}
          eager={props.eager}
        />
        <span className="card-play" aria-hidden="true"><Icon name="play" /></span>
        {percent > 0 && percent < 100 ? (
          <span className="card-progress" aria-label={`${percent} Prozent gesehen`}>
            <i style={{ width: `${percent}%` }} />
          </span>
        ) : null}
      </span>
      <span className="card-title">{props.title}</span>
      {props.subtitle ? <span className="card-sub">{props.subtitle}</span> : null}
    </button>
    {props.onRemove ? (
      <button
        type="button"
        className="card-remove"
        title="Aus „Weiterschauen“ entfernen"
        aria-label={`${props.title} aus „Weiterschauen“ entfernen`}
        onClick={props.onRemove}
      >
        <Icon name="close" />
      </button>
    ) : null}
    </div>
  );
}, sameCard);

function sameCard(a: CardProps & { still?: string | null }, b: CardProps & { still?: string | null }): boolean {
  return a.slug === b.slug && a.provider === b.provider && a.title === b.title
    && a.subtitle === b.subtitle && a.percent === b.percent && a.eager === b.eager
    && a.still === b.still && a.onSelect === b.onSelect
    && (a as { onRemove?: unknown }).onRemove === (b as { onRemove?: unknown }).onRemove
    && (a.alts?.join("|") ?? "") === (b.alts?.join("|") ?? "");
}

/** Eine Folge in der Liste der Detailseite. */
export function EpisodeRow({
  number, label, meta, state, done, still, slug, provider, seriesTitle, percent,
  onSelect, onToggleWatched,
}: {
  number: number;
  label: string;
  meta: string;
  state: string | null;
  done: boolean;
  still?: string | null;
  slug: string;
  provider: CatalogProvider;
  seriesTitle: string;
  percent: number;
  onSelect(): void;
  /**
   * Haken setzen oder wegnehmen.
   *
   * Ein eigener Knopf und kein Kontextmenü: ein Befehl, den man nicht findet,
   * gibt es nicht. Er liegt am rechten Rand der Zeile, ist mit der Tastatur
   * erreichbar und trägt seinen Zustand über `aria-pressed`. Die Regel
   * dahinter steht im Kern (`WatchMarks`) und gilt genauso auf dem Fernseher,
   * dem iPhone und dem Mac.
   */
  onToggleWatched?(): void;
}) {
  return (
    <div className={`ep-wrap${done ? " done" : ""}`}>
    <button type="button" className={`ep${done ? " done" : ""}`} onClick={onSelect}>
      <span className="ep-thumb" data-nav-quiet="">
        <Artwork
          kind={"still" as ArtworkKind}
          src={still}
          slug={slug}
          provider={provider}
          title={seriesTitle}
          passive
        />
        <span className="ep-badge" aria-hidden="true">{number}</span>
        {percent > 0 && !done ? (
          <span className="card-progress" aria-hidden="true"><i style={{ width: `${percent}%` }} /></span>
        ) : null}
      </span>
      <span className="ep-body">
        <span className="ep-title">{number}. {label}</span>
        <span className="ep-meta">{meta || " "}</span>
        <span className={`ep-state${done ? " done" : ""}`}>{state ?? " "}</span>
      </span>
    </button>
    {onToggleWatched ? (
      <button
        type="button"
        className={`ep-mark${done ? " done" : ""}`}
        aria-pressed={done}
        title={done ? "Als ungesehen markieren" : "Als gesehen markieren"}
        aria-label={`Folge ${number} ${done ? "als ungesehen" : "als gesehen"} markieren`}
        onClick={onToggleWatched}
      >
        <Icon name="check" />
      </button>
    ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Kopfbereich

export function Hero({ slug, provider, title, alts, eyebrow, backdrop, logo, meta, description, progress, actions }: {
  slug: string;
  provider: CatalogProvider;
  title: string;
  alts?: string[];
  eyebrow?: string;
  backdrop?: string | null;
  logo?: string | null;
  meta: ReactNode;
  description?: string;
  progress?: { percent: number; label: string } | null;
  actions: ReactNode;
}) {
  const [logoFailed, setLogoFailed] = useState(false);
  useEffect(() => setLogoFailed(false), [logo]);

  return (
    <section className="hero" aria-label={title}>
      <div className="hero-media" data-nav-quiet="">
        <Artwork
          kind="hero"
          src={backdrop}
          slug={slug}
          provider={provider}
          title={title}
          alts={alts}
          eager
        />
      </div>
      <div className="hero-shade" aria-hidden="true" />
      <div className="hero-copy">
        {eyebrow ? <div className="eyebrow">{eyebrow}</div> : null}
        {logo && !logoFailed ? (
          <img className="hero-logo" src={logo} alt={title} onError={() => setLogoFailed(true)} />
        ) : (
          <h2>{title}</h2>
        )}
        <div className="meta">{meta}</div>
        <p className="hero-text">{description ?? ""}</p>
        {progress && progress.percent > 0 && progress.percent < 100 ? (
          <div className="hero-progress">
            <span className="hero-progress-bar"><i style={{ width: `${progress.percent}%` }} /></span>
            <small>{progress.label}</small>
          </div>
        ) : null}
        <div className="hero-actions">{actions}</div>
      </div>
    </section>
  );
}

// ---------------------------------------------------------------------------
// Zustände

export function EmptyState({ title, message, action }: { title: string; message: string; action?: ReactNode }) {
  return (
    <div className="state">
      <h2>{title}</h2>
      <p>{message}</p>
      {action}
    </div>
  );
}

export function ErrorState({ title, message, onRetry }: { title: string; message: string; onRetry?: () => void }) {
  return (
    <div className="state" role="alert">
      <h2>{title}</h2>
      <p>{message}</p>
      {onRetry ? (
        <button type="button" className="btn primary" onClick={onRetry}>
          <Icon name="refresh" /><span>Erneut versuchen</span>
        </button>
      ) : null}
    </div>
  );
}

/** Platzhalter in der Form dessen, was kommt — damit beim Eintreffen nichts springt. */
export function GridSkeleton({ count = 12, wide = false }: { count?: number; wide?: boolean }) {
  return (
    <div className={`grid${wide ? " wide" : ""}`} aria-hidden="true">
      {Array.from({ length: count }, (_, index) => (
        <div className="card poster" key={index}>
          <div className={`card-art ${wide ? "land-art" : "poster-art"} skeleton`} />
          <div className="skeleton-line" style={{ width: "72%" }} />
        </div>
      ))}
    </div>
  );
}

export function RailSkeleton({ count = 7, wide = false }: { count?: number; wide?: boolean }) {
  return (
    <div className="rail-wrap">
      <div className="rail" aria-hidden="true">
        {Array.from({ length: count }, (_, index) => (
          <div className={`card ${wide ? "land" : "poster"}`} key={index}>
            <div className={`card-art ${wide ? "land-art" : "poster-art"} skeleton`} />
            <div className="skeleton-line" style={{ width: "72%" }} />
          </div>
        ))}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Dialog

/**
 * Ein Dialog.
 *
 * Escape schließt, ein Klick daneben schließt, und der Fokus wandert beim
 * Öffnen hinein — drei Dinge, die auf dem Schreibtisch jeder erwartet und die
 * keine davon von selbst passiert.
 */
export function Dialog({ open, title, description, onClose, children, actions }: {
  open: boolean;
  title: string;
  description?: string;
  onClose(): void;
  children?: ReactNode;
  actions?: ReactNode;
}) {
  const box = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return undefined;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.stopPropagation();
        onClose();
      }
    };
    window.addEventListener("keydown", onKey, true);
    box.current?.querySelector<HTMLElement>("button, input, select")?.focus();
    return () => window.removeEventListener("keydown", onKey, true);
  }, [open, onClose]);

  if (!open) return null;
  return (
    <>
      <div className="dialog-shade" onClick={onClose} />
      <div className="dialog" role="dialog" aria-modal="true" aria-label={title} ref={box}>
        <h2>{title}</h2>
        {description ? <p>{description}</p> : null}
        {children}
        <div className="dialog-actions">{actions ?? (
          <button type="button" className="btn" onClick={onClose}>Schließen</button>
        )}</div>
      </div>
    </>
  );
}

// ---------------------------------------------------------------------------
// Einstellungszeilen

export function Row({ label, hint, value, onClick, icon }: {
  label: string;
  hint?: string;
  value?: ReactNode;
  onClick?: () => void;
  icon?: IconName;
}) {
  const body = (
    <>
      <span className="row-copy">
        <b>{label}</b>
        {hint ? <small>{hint}</small> : null}
      </span>
      <span className="row-value">
        {value}
        {onClick ? <Icon name={icon ?? "chevronRight"} /> : null}
      </span>
    </>
  );
  if (!onClick) return <div className="row">{body}</div>;
  return <button type="button" className="row" onClick={onClick}>{body}</button>;
}

export function Toggle({ label, hint, value, onChange }: {
  label: string;
  hint?: string;
  value: boolean;
  onChange(next: boolean): void;
}) {
  return (
    <button
      type="button"
      className="row"
      role="switch"
      aria-checked={value}
      onClick={() => onChange(!value)}
    >
      <span className="row-copy">
        <b>{label}</b>
        {hint ? <small>{hint}</small> : null}
      </span>
      <span className="row-value">
        <span>{value ? "An" : "Aus"}</span>
        <span className={`switch${value ? " on" : ""}`} aria-hidden="true" />
      </span>
    </button>
  );
}

export function Select<T extends string>({ label, hint, value, options, onChange }: {
  label: string;
  hint?: string;
  value: T;
  options: { value: T; label: string }[];
  onChange(next: T): void;
}) {
  return (
    <div className="row">
      <span className="row-copy">
        <b>{label}</b>
        {hint ? <small>{hint}</small> : null}
      </span>
      <span className="row-value">
        <select
          className="select"
          value={value}
          aria-label={label}
          onChange={(event) => onChange(event.target.value as T)}
        >
          {options.map((option) => (
            <option key={option.value} value={option.value}>{option.label}</option>
          ))}
        </select>
      </span>
    </div>
  );
}
