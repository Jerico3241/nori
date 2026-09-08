// Anbindung des Videoelements.
//
// Reihenfolge wie in der Aufgabenstellung: direkt spielbar zuerst, dann
// natives HLS, erst danach hls.js. Auf webOS ist natives HLS der bessere Weg —
// es läuft in der Hardware, während hls.js jedes Segment durch JavaScript
// schleust und auf älteren Panels sichtbar ruckelt.
//
// Der Rest dieser Datei ist Aufräumen. Ein Player, der beim Verlassen nicht
// vollständig abgebaut wird, lädt im Hintergrund weiter Segmente; nach ein paar
// Folgen ist der Speicher voll und der Fernseher langsam.

import Hls, { type ErrorData, Events } from "hls.js";
import type { PlayKind } from "@nori/core";
import { log, warn } from "../services/log";

export type PlaybackEngine = "native" | "hls.js";

export interface AttachOptions {
  video: HTMLVideoElement;
  url: string;
  kind: PlayKind;
  startAt: number;
  onFatal(message: string): void;
  onEngine(engine: PlaybackEngine): void;
}

export interface Playback {
  destroy(): void;
  readonly engine: PlaybackEngine;
}

const MAX_NETWORK_RETRIES = 3;

export function attachPlayback(options: AttachOptions): Playback {
  const { video, url, kind, startAt } = options;

  const seekOnce = () => {
    if (startAt > 0 && Number.isFinite(video.duration) && video.currentTime < startAt) {
      video.currentTime = startAt;
    }
    video.removeEventListener("loadedmetadata", seekOnce);
  };
  video.addEventListener("loadedmetadata", seekOnce);

  const nativeHls = video.canPlayType("application/vnd.apple.mpegurl") !== ""
    || video.canPlayType("application/x-mpegURL") !== "";

  if (kind === "mp4" || nativeHls) {
    log("playback", "native Wiedergabe", kind, nativeHls ? "mit HLS" : "ohne HLS");
    options.onEngine("native");
    video.src = url;
    const onError = () => {
      const code = video.error?.code;
      options.onFatal(`Wiedergabe abgebrochen (Code ${code ?? "?"})`);
    };
    video.addEventListener("error", onError);
    void video.play().catch((cause: unknown) => {
      log("playback", "Autostart abgelehnt", (cause as Error)?.message);
    });
    return {
      engine: "native",
      destroy() {
        video.removeEventListener("error", onError);
        video.removeEventListener("loadedmetadata", seekOnce);
        teardownVideo(video);
      },
    };
  }

  if (!Hls.isSupported()) {
    options.onFatal("Dieser Fernseher kann den Stream nicht abspielen (kein HLS).");
    return { engine: "native", destroy: () => teardownVideo(video) };
  }

  log("hls", "hls.js wird benutzt");
  options.onEngine("hls.js");
  const hls = new Hls({
    // Kleine Puffer: ein Fernseher hat wenig Speicher, und 60 s Vorrat sind
    // mehr, als eine Folge je braucht.
    maxBufferLength: 30,
    maxMaxBufferLength: 60,
    backBufferLength: 30,
    enableWorker: true,
    lowLatencyMode: false,
    manifestLoadingMaxRetry: 2,
    levelLoadingMaxRetry: 2,
    fragLoadingMaxRetry: 3,
  });

  let networkRetries = 0;
  const onHlsError = (_event: unknown, data: ErrorData) => {
    if (!data.fatal) return;
    switch (data.type) {
      case Hls.ErrorTypes.NETWORK_ERROR:
        networkRetries += 1;
        if (networkRetries > MAX_NETWORK_RETRIES) {
          warn("hls", "Netzwerkfehler endgültig", data.details);
          options.onFatal(`Netzwerkfehler beim Laden des Streams (${data.details}).`);
          return;
        }
        // Begrenzter Wiederholungsversuch, keine Endlosschleife.
        log("hls", "Netzwerkfehler, neuer Versuch", networkRetries, data.details);
        hls.startLoad();
        return;
      case Hls.ErrorTypes.MEDIA_ERROR:
        log("hls", "Medienfehler, Wiederherstellung", data.details);
        hls.recoverMediaError();
        return;
      default:
        warn("hls", "Fataler Fehler", data.type, data.details);
        options.onFatal(`Stream nicht abspielbar (${data.details}).`);
    }
  };

  hls.on(Events.ERROR, onHlsError);
  hls.loadSource(url);
  hls.attachMedia(video);
  hls.on(Events.MANIFEST_PARSED, () => {
    void video.play().catch((cause: unknown) => {
      log("playback", "Autostart abgelehnt", (cause as Error)?.message);
    });
  });

  return {
    engine: "hls.js",
    destroy() {
      hls.off(Events.ERROR, onHlsError);
      video.removeEventListener("loadedmetadata", seekOnce);
      try {
        hls.stopLoad();
        hls.detachMedia();
        hls.destroy();
      } catch (cause) {
        warn("hls", "Abbau meldete einen Fehler", (cause as Error)?.message);
      }
      teardownVideo(video);
    },
  };
}

/**
 * Das Videoelement wirklich losbinden.
 *
 * `pause()` allein reicht nicht: solange eine Quelle gesetzt ist, lädt der
 * Fernseher weiter. Erst `removeAttribute("src")` samt `load()` beendet das.
 */
function teardownVideo(video: HTMLVideoElement): void {
  try {
    video.pause();
    video.removeAttribute("src");
    while (video.firstChild) video.removeChild(video.firstChild);
    video.load();
  } catch (cause) {
    warn("playback", "Abbau des Videoelements", (cause as Error)?.message);
  }
}
