// Ein Bild, das das Layout nicht verschieben kann.
//
// Die Fläche ist vorher reserviert: das Element füllt eine Box mit festem
// Seitenverhältnis, die der Aufrufer zeichnet. Ob ein Bild kommt, später kommt
// oder scheitert, ändert an keiner Kachel die Größe — und damit an keiner
// Fokusposition.
//
// ## Welches Bild
//
// Eine Liste in absteigender Güte, die bei jedem Zeichnen neu entsteht:
//
//     übergebene Adresse (Standbild einer Folge, Breitbild des Kopfbereichs)
//     TMDB-Breitbild            (nicht bei Postern)
//     TMDB-Poster
//     Cover der Quelle
//
// Scheitert eine Adresse, wird sie gemerkt und die nächste genommen. Am Ende
// steht ein Ersatz aus dem Titel, nie eine Lücke. Die Größe jeder TMDB-Adresse
// setzt `services/images.ts` — eine Kachel lädt kein Kopfbild, und das
// Kopfbild eines 4K-Panels ist kein gestrecktes `w1280`.
//
// ## Wann es geladen wird
//
// Erst in Sichtweite, außer bei `eager`. Und **auch dann, wenn schon ein
// Quellcover da ist**: der vorherige Stand fragte TMDB nur, wenn gar kein Bild
// bekannt war. Ein einmal abgelegtes 220-px-Quellcover verhinderte damit für
// immer das scharfe TMDB-Poster.

import type { CatalogProvider } from "@nori/core";
import { useEffect, useRef, useState } from "react";

import { covers } from "../services/covers";
import { sizedImage, type ImageUse } from "../services/images";
import { tmdb } from "../services/tmdb";
import { useData } from "../state/data";

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

export function Artwork({
  kind, slug, provider, title, alts, src, fallback, eager = false, passive = false, className,
}: {
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
}) {
  const { gateway, tmdbRoute } = useData();
  const [, setVersion] = useState(0);
  const [failed, setFailed] = useState<string[]>([]);
  const [loadedUrl, setLoadedUrl] = useState<string | null>(null);
  const holder = useRef<HTMLSpanElement>(null);

  // Ein Treffer, der später eintrifft, muss die Kachel erreichen.
  useEffect(() => covers.subscribe((changed) => {
    if (changed === slug || changed === "*") setVersion((value) => value + 1);
  }), [slug]);

  useEffect(() => {
    setFailed([]);
  }, [slug, provider, src]);

  useEffect(() => {
    if (passive || (kind === "still" && src)) return undefined;
    const wantsTmdb = tmdb.available && !covers.hasTmdb(slug, provider);
    const hasAny = candidatesFor(kind, slug, provider, src, fallback).length > 0;
    if (!wantsTmdb && hasAny) return undefined;

    let cancelled = false;
    const run = () => {
      void covers.ensure({ slug, provider, title, alts }).then(() => {
        if (!cancelled) setVersion((value) => value + 1);
      });
    };
    if (eager || !("IntersectionObserver" in window)) {
      run();
      return () => {
        cancelled = true;
      };
    }
    const node = holder.current;
    if (!node) return undefined;
    const observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) {
        observer.disconnect();
        run();
      }
    }, { rootMargin: "360px 480px" });
    observer.observe(node);
    return () => {
      cancelled = true;
      observer.disconnect();
    };
    // `title` und `alts` absichtlich außen vor: sie ändern sich beim Nachladen
    // der Detaildaten, und das darf keinen zweiten Abruf auslösen.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [kind, slug, provider, src, eager, passive, tmdbRoute.effective]);

  const entry = candidatesFor(kind, slug, provider, src, fallback)
    .find((candidate) => !failed.includes(candidate.url));
  const sized = entry ? sizedImage(entry.url, entry.use) : null;
  const url = sized ? gateway.imageURL(sized, provider) : null;
  const loaded = url !== null && loadedUrl === url;

  return (
    <span className={`art${className ? ` ${className}` : ""}`} ref={holder}>
      {url ? (
        <img
          key={url}
          src={url}
          alt=""
          className={loaded ? "loaded" : ""}
          loading={eager ? "eager" : "lazy"}
          decoding="async"
          onLoad={() => setLoadedUrl(url)}
          onError={() => {
            if (entry) setFailed((list) => (list.includes(entry.url) ? list : [...list, entry.url]));
          }}
        />
      ) : null}
      {!loaded ? <span className="art-fallback" aria-hidden="true">{initialsOf(title)}</span> : null}
    </span>
  );
}
