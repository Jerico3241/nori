// Ein Bild, das das Layout nicht kaputt machen kann.
//
// Kaputte Cover sind bei beiden Quellen Alltag — Hotlink-Sperren, gewechselte
// Dateinamen, AVIF, das der Fernseher nicht mag. Deshalb hat die Kachel immer
// dieselbe Größe, das Bild wird eingeblendet statt eingesetzt, und wenn nichts
// kommt, steht dort ein Ersatzbild aus dem Titel statt einer Lücke.

import { useEffect, useRef, useState } from "react";
import type { CatalogProvider } from "@nori/core";
import { covers } from "../services/covers";
import { useData } from "../state/data";

interface PosterImageProps {
  slug: string;
  provider: CatalogProvider;
  title: string;
  /** Bereits bekannte Adresse; sonst wird sie über den Cover-Index besorgt. */
  src?: string | null;
  /** Erst laden, wenn die Kachel in der Nähe des Bildschirms ist. */
  eager?: boolean;
  className?: string;
}

export function PosterImage({ slug, provider, title, src, eager = false, className }: PosterImageProps) {
  const { gateway } = useData();
  const [url, setUrl] = useState<string | null>(src ?? covers.cached(slug, provider));
  const [loaded, setLoaded] = useState(false);
  const [failed, setFailed] = useState(false);
  const holder = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setUrl(src ?? covers.cached(slug, provider));
    setLoaded(false);
    setFailed(false);
  }, [slug, provider, src]);

  useEffect(() => {
    if (url || src) return;
    let cancelled = false;
    const fetchCover = () => {
      void covers.ensure(slug, provider).then((found) => {
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
  }, [url, src, slug, provider, eager]);

  const initials = title.replace(/[^\p{L}\p{N} ]/gu, "").trim().split(/\s+/)
    .slice(0, 2).map((word) => word[0] ?? "").join("").toUpperCase() || "N";

  return (
    <div className={`poster ${className ?? ""}`} ref={holder}>
      {url && !failed ? (
        <img
          src={gateway.imageURL(url, provider)}
          alt=""
          className={loaded ? "loaded" : ""}
          loading={eager ? "eager" : "lazy"}
          onLoad={() => setLoaded(true)}
          onError={() => setFailed(true)}
        />
      ) : null}
      {(!url || failed || !loaded) ? <span className="poster-fallback">{initials}</span> : null}
    </div>
  );
}
