// Ein Bild, das das Layout nicht verschieben kann.
//
// Die Fläche ist vorher reserviert: das Element füllt eine Box mit festem
// Seitenverhältnis, die der Aufrufer zeichnet. Ob ein Bild kommt, später kommt
// oder scheitert, ändert an keiner Kachel die Größe — und damit an keiner
// Fokusposition.
//
// ## Welches Bild
//
// Eine Liste in absteigender Güte:
//
//     übergebene Adresse (Standbild einer Folge, Breitbild des Kopfbereichs)
//     TMDB-Breitbild            (nicht bei Postern)
//     TMDB-Poster
//     Cover der Quelle
//
// Scheitert eine Adresse, wird sie gemerkt und die nächste genommen. Am Ende
// steht ein Ersatz aus dem Titel, nie eine Lücke. Die Größe jeder TMDB-Adresse
// setzt `services/images.ts` — eine Kachel lädt kein Kopfbild, und das
// Kopfbild eines 4K-Panels ist kein `original` für eine 1080p-Fläche.
//
// ## Wann es geladen wird
//
// Zwei Stufen, und das ist der Unterschied zum vorherigen Stand:
//
// 1. **Nachfragen** (TMDB nach diesem Titel fragen) passiert, sobald die
//    Kachel in die Nähe des Bildes kommt.
// 2. **Laden** (`src` setzen) passiert erst, wenn dafür ein Platz frei ist —
//    `services/artworkQueue.ts` lässt drei bis vier gleichzeitig zu und
//    bevorzugt Kopfbereich und fokussierte Kachel.
//
// Vorher stand die Adresse sofort im `src` jeder gezeichneten Kachel, und der
// Browser lud, was er für richtig hielt. Auf der Startseite waren das über
// hundert Bilder in den ersten Sekunden.
//
// ## Geteilt zwischen Fernseher und Schreibtisch
//
// Die Klassennamen (`art`, `art-fallback`, `loaded`) sind der einzige Berührungs-
// punkt mit der Oberfläche; wie eine Bildfläche aussieht, entscheidet jede App
// in ihrem Stylesheet. Alles andere — welches Bild, in welcher Größe, wann
// geladen — ist überall dasselbe und steht deshalb nur einmal hier.
//
// Und die Nachfrage läuft **auch dann, wenn schon ein Quellcover da ist**: der
// ältere Stand fragte TMDB nur, wenn gar kein Bild bekannt war. Ein einmal
// abgelegtes 220-px-Quellcover verhinderte damit für immer das scharfe
// TMDB-Poster.

import type { CatalogProvider } from "@nori/core";
import { memo, useEffect, useMemo, useRef, useState } from "react";

import {
  ARTWORK_PRIORITY,
  covers,
  performanceProfile,
  requestArtworkSlot,
  sizedImage,
  tmdb,
  useData,
  type ImageUse,
} from "@nori/app";

export type ArtworkKind = "poster" | "backdrop" | "hero" | "still";

interface Candidate {
  url: string;
  use: ImageUse;
}

function candidatesFor(
  kind: ArtworkKind,
  slug: string,
  provider: CatalogProvider,
  src?: string | null,
  fallback?: string | null,
): Candidate[] {
  const out: Candidate[] = [];
  const push = (url: string | null | undefined, use: ImageUse) => {
    if (url && !out.some((entry) => entry.url === url)) out.push({ url, use });
  };
  const art = tmdb.art(slug, provider);
  const wide: ImageUse = kind === "hero" ? "backdropHero" : "backdropCard";

  if (src) push(src, kind === "still" ? "still" : kind === "poster" ? "poster" : wide);
  if (kind !== "poster") push(art?.backdrop, wide);
  push(art?.poster, "poster");
  push(covers.sourceCover(slug, provider), "poster");
  push(fallback, "poster");
  return out;
}

function initialsOf(title: string): string {
  return title.replace(/[^\p{L}\p{N} ]/gu, "").trim().split(/\s+/)
    .slice(0, 2).map((word) => word[0] ?? "").join("").toUpperCase() || "N";
}

export interface ArtworkProps {
  kind: ArtworkKind;
  slug: string;
  provider: CatalogProvider;
  title: string;
  alts?: string[];
  src?: string | null;
  /** Ein letzter Rückfall, etwa das Cover aus dem Kalender der Quelle. */
  fallback?: string | null;
  eager?: boolean;
  /** Keinen Abruf anstoßen — nur zeigen, was schon bekannt ist. */
  passive?: boolean;
  className?: string;
}

function ArtworkView({
  kind, slug, provider, title, alts, src, fallback, eager = false, passive = false, className,
}: ArtworkProps) {
  const { gateway, tmdbRoute } = useData();
  const [version, setVersion] = useState(0);
  const [failed, setFailed] = useState<string[]>([]);
  const [loadedUrl, setLoadedUrl] = useState<string | null>(null);
  /** Die Adresse, für die ein Platz vergeben wurde — erst sie kommt ins `src`. */
  const [claimed, setClaimed] = useState<string | null>(null);
  /** Ist die Kachel nahe genug am Bild, um überhaupt etwas zu wollen? */
  const [near, setNear] = useState(eager);
  const holder = useRef<HTMLSpanElement>(null);

  // Ein Treffer, der später eintrifft, muss die Kachel erreichen — und nur sie.
  useEffect(
    () => covers.subscribe(slug, () => setVersion((value) => value + 1)),
    [slug],
  );

  useEffect(() => {
    setFailed([]);
    setClaimed(null);
    setLoadedUrl(null);
  }, [slug, provider, src]);

  // Sichtweite. `eager` überspringt das; alles andere wartet, bis die Kachel
  // in die Nähe kommt. Ohne `IntersectionObserver` (sehr alte Stände) gilt
  // alles als nah — lieber zu viel laden als gar nichts zeigen.
  useEffect(() => {
    if (eager || near) return undefined;
    if (!("IntersectionObserver" in window)) {
      setNear(true);
      return undefined;
    }
    const node = holder.current;
    if (!node) return undefined;
    const observer = new IntersectionObserver((entries) => {
      if (!entries.some((entry) => entry.isIntersecting)) return;
      observer.disconnect();
      setNear(true);
    }, { rootMargin: performanceProfile().prefetchMargin });
    observer.observe(node);
    return () => observer.disconnect();
  }, [eager, near]);

  const entries = useMemo(
    () => candidatesFor(kind, slug, provider, src, fallback),
    // `version` ist der Anstoß: kommt ein Cover an, entsteht die Liste neu.
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [kind, slug, provider, src, fallback, version],
  );

  // Nachfragen bei TMDB, sobald die Kachel in die Nähe kommt.
  useEffect(() => {
    if (passive || !near || (kind === "still" && src)) return undefined;
    const wantsTmdb = tmdb.available && !covers.hasTmdb(slug, provider);
    if (!wantsTmdb && entries.length > 0) return undefined;

    let cancelled = false;
    void covers.ensure({ slug, provider, title, alts }).then(() => {
      if (!cancelled) setVersion((value) => value + 1);
    });
    return () => {
      cancelled = true;
    };
    // `title` und `alts` absichtlich außen vor: sie ändern sich beim Nachladen
    // der Detaildaten, und das darf keinen zweiten Abruf auslösen. `entries`
    // ebenso — sonst liefe der Abruf bei jedem eintreffenden Cover erneut.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [kind, slug, provider, src, near, passive, tmdbRoute.effective]);

  const entry = entries.find((candidate) => !failed.includes(candidate.url));
  const sized = entry ? sizedImage(entry.url, entry.use) : null;
  const url = sized ? gateway.imageURL(sized, provider) : null;

  // Einen Platz holen, sobald feststeht, welches Bild es werden soll.
  useEffect(() => {
    if (!near || !url || url === claimed) return undefined;
    const priority = kind === "hero"
      ? ARTWORK_PRIORITY.hero
      : holder.current && document.activeElement instanceof HTMLElement
        && document.activeElement.contains(holder.current)
        ? ARTWORK_PRIORITY.hero
        : eager ? ARTWORK_PRIORITY.eager : ARTWORK_PRIORITY.visible;
    const slot = requestArtworkSlot(priority, () => setClaimed(url));
    return () => slot.release();
  }, [near, url, claimed, kind, eager]);

  const shown = url !== null && claimed === url ? url : null;
  const loaded = shown !== null && loadedUrl === shown;

  return (
    <span className={`art${className ? ` ${className}` : ""}`} ref={holder}>
      {shown ? (
        <img
          key={shown}
          src={shown}
          alt=""
          className={loaded ? "loaded" : ""}
          decoding="async"
          onLoad={() => setLoadedUrl(shown)}
          onError={() => {
            if (entry) setFailed((list) => (list.includes(entry.url) ? list : [...list, entry.url]));
          }}
        />
      ) : null}
      {!loaded ? <span className="art-fallback" aria-hidden="true">{initialsOf(title)}</span> : null}
    </span>
  );
}

/**
 * Gleiche Angaben, gleiches Bild.
 *
 * Eine Kachel zeichnet sich sonst bei jedem Durchgang der Reihe neu, obwohl
 * sich an ihr nichts geändert hat — und eine Reihe zeichnet sich neu, sobald
 * irgendein TMDB-Treffer die Startseite anfasst. `alts` ist ein Feld und bei
 * jedem Durchgang ein neues Objekt; verglichen wird deshalb sein Inhalt.
 */
export const Artwork = memo(ArtworkView, (a, b) =>
  a.kind === b.kind && a.slug === b.slug && a.provider === b.provider
  && a.title === b.title && a.src === b.src && a.fallback === b.fallback
  && a.eager === b.eager && a.passive === b.passive && a.className === b.className
  && (a.alts?.join("|") ?? "") === (b.alts?.join("|") ?? ""));
