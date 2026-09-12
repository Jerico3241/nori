// Ein Bild, das das Layout nicht kaputt machen kann.
//
// Kaputte Cover sind bei beiden Quellen Alltag — Hotlink-Sperren, gewechselte
// Dateinamen, AVIF, das der Fernseher nicht mag. Deshalb hat die Kachel immer
// dieselbe Größe, das Bild wird eingeblendet statt eingesetzt, und wenn nichts
// kommt, steht dort ein Ersatzbild aus dem Titel statt einer Lücke.
//
// Drei Dinge, die hier zusammenkommen:
//
// - **Nachladen erst in Sichtweite.** Ein Raster mit sechzig Kacheln lädt
//   sonst sechzig Bilder auf einmal.
// - **Ein Rückfall je Stufe.** Scheitert das TMDB-Bild, wird das Cover der
//   Quelle versucht; scheitert auch das, bleibt der Buchstabe. Ein `onError`,
//   der nur aufgibt, macht aus einem Hotlink-Fehler eine leere Kachel.
// - **Nachträgliche Treffer.** Ein TMDB-Treffer trifft Sekunden nach dem
//   Rendern ein. Ohne die Anmeldung am Bildindex stünde bis zum nächsten
//   Seitenwechsel weiter das Quellcover.

import { useEffect, useRef, useState } from "react";
import type { CatalogProvider } from "@nori/core";
import { covers } from "../services/covers";
import { useData } from "../state/data";

interface PosterImageProps {
  slug: string;
  provider: CatalogProvider;
  title: string;
  /** Alternativtitel der Quelle — sie entscheiden über den TMDB-Treffer. */
  alts?: string[];
  /** Bereits bekannte Adresse; sonst wird sie über den Bildindex besorgt. */
  src?: string | null;
  /** Erst laden, wenn die Kachel in der Nähe des Bildschirms ist. */
  eager?: boolean;
  className?: string;
  /** Kein TMDB-Abruf anstoßen — für Listen, die nur zeigen, was schon da ist. */
  passive?: boolean;
}

export function PosterImage({
  slug, provider, title, alts, src, eager = false, className, passive = false,
}: PosterImageProps) {
  const { gateway } = useData();
  const [url, setUrl] = useState<string | null>(src ?? covers.cached(slug, provider));
  const [loaded, setLoaded] = useState(false);
  /** Adressen, die dieses Bild schon abgelehnt hat. */
  const [failed, setFailed] = useState<string[]>([]);
  const holder = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setUrl(src ?? covers.cached(slug, provider));
    setLoaded(false);
    setFailed([]);
  }, [slug, provider, src]);

  // Ein Treffer, der später eintrifft, muss die Kachel erreichen.
  useEffect(() => {
    if (src) return;
    return covers.subscribe((changed) => {
      if (changed !== slug && changed !== "*") return;
      const best = covers.cached(slug, provider);
      if (best) setUrl((current) => (current === best ? current : best));
    });
  }, [slug, provider, src]);

  useEffect(() => {
    if (url || src || passive) return;
    let cancelled = false;
    const fetchCover = () => {
      void covers.ensure({ slug, provider, title, alts }).then((found) => {
        if (!cancelled && found) setUrl(found);
      });
    };
    if (eager || !("IntersectionObserver" in window)) {
      fetchCover();
      return () => {
        cancelled = true;
      };
    }
    // Nicht hunderte Bilder gleichzeitig: geholt wird, was in Sichtweite kommt.
    const node = holder.current;
    if (!node) return;
    const observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) {
        observer.disconnect();
        fetchCover();
      }
    }, { rootMargin: "600px 900px" });
    observer.observe(node);
    return () => {
      cancelled = true;
      observer.disconnect();
    };
    // `title` und `alts` absichtlich außen vor: sie ändern sich beim Nachladen
    // der Detaildaten, und das darf keinen zweiten Abruf auslösen.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [url, src, slug, provider, eager, passive]);

  const shown = url && !failed.includes(url) ? url : null;
  const initials = title.replace(/[^\p{L}\p{N} ]/gu, "").trim().split(/\s+/)
    .slice(0, 2).map((word) => word[0] ?? "").join("").toUpperCase() || "N";

  return (
    <div className={`poster ${className ?? ""}`} ref={holder}>
      {shown ? (
        <img
          src={gateway.imageURL(shown, provider)}
          alt=""
          className={loaded ? "loaded" : ""}
          loading={eager ? "eager" : "lazy"}
          onLoad={() => setLoaded(true)}
          onError={() => {
            setFailed((list) => [...list, shown]);
            setLoaded(false);
            // Eine Stufe tiefer statt aufgeben: ein TMDB-Bild, das der
            // Fernseher nicht lädt, heißt nicht, dass es kein Cover gibt.
            const fallback = covers.sourceCover(slug, provider);
            setUrl(fallback && fallback !== shown ? fallback : null);
          }}
        />
      ) : null}
      {(!shown || !loaded) ? <span className="poster-fallback">{initials}</span> : null}
    </div>
  );
}
