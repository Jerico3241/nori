// Der Player.
//
// Alles, was auf dem Fernseher passiert, während etwas läuft: auflösen,
// abspielen, Fortschritt sichern, Hoster und Sprache wechseln, zur nächsten
// Folge übergehen — und beim Verlassen restlos abbauen.
//
// Zurück-Reihenfolge, bewusst dreistufig: Drawer schließen, dann Bedienung
// schließen, erst dann den Player verlassen. Ein Zurück, das aus dem Drawer
// heraus sofort zur Detailseite springt, verliert die Wiedergabe für einen
// Tastendruck, der nur „einen Schritt zurück" meinte.

import {
  NoriError, availableLanguages, episodePathFor, nextEpisode, orderHosters, previousEpisode,
  resumePosition,
  type CatalogProvider, type Episode, type HosterOption, type PlaySource, type SeriesDetail,
  type WatchInfo,
} from "@nori/core";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useParams, useSearchParams } from "react-router-dom";

import { Icon } from "../components/Icon";
import { useBackHandler } from "../navigation/back";
import { SpotArea, SpotButton, useAutoFocus } from "../navigation/Spot";
import { arrowDirection, isBack, isEnter, isPause, isPlay, isPlayPause, isStop, seekDirection } from "../navigation/keys";
import { log, warn } from "../services/log";
import { keepAwake } from "../services/webos";
import { useData } from "../state/data";
import { useLibrary } from "../state/library";
import { useSettings } from "../state/settings";
import { PlayerControls } from "./PlayerControls";
import { PlayerDrawer } from "./PlayerDrawer";
import { attachPlayback, type Playback } from "./hlsPlayback";

type Phase = "resolving" | "playing" | "error";
type Overlay = "none" | "resume" | "next";

function isProvider(value: string | undefined): value is CatalogProvider {
  return value === "aniworld" || value === "serienstream";
}

/** Beschleunigtes Spulen beim Halten der Taste — wie bei einem Videorekorder. */
function seekMultiplier(heldMs: number): number {
  if (heldMs >= 8000) return 3;
  if (heldMs >= 4000) return 2;
  return 1;
}

export function PlayerPage() {
  const params = useParams<{ provider: string; slug: string }>();
  const [search, setSearch] = useSearchParams();
  const navigate = useNavigate();
  const { series, watch, gateway } = useData();
  const library = useLibrary();
  const { settings } = useSettings();

  const provider: CatalogProvider = isProvider(params.provider) ? params.provider : "aniworld";
  const slug = decodeURIComponent(params.slug ?? "");
  const season = search.get("season") ?? "1";
  const episodeNumber = Number(search.get("episode") ?? "1") || 1;
  const requestedPath = search.get("path") ?? "";
  const requestedAt = Number(search.get("at") ?? "0") || 0;

  const videoRef = useRef<HTMLVideoElement>(null);
  const playbackRef = useRef<Playback | null>(null);

  const [detail, setDetail] = useState<SeriesDetail | null>(null);
  const [info, setInfo] = useState<WatchInfo | null>(null);
  const [source, setSource] = useState<PlaySource | null>(null);
  const [phase, setPhase] = useState<Phase>("resolving");
  const [statusText, setStatusText] = useState("Stream wird gesucht …");
  const [errorText, setErrorText] = useState("");
  const [failedHosters, setFailedHosters] = useState<string[]>([]);

  const [lang, setLang] = useState(library.state.langPref);
  const [chrome, setChrome] = useState(true);
  const [paused, setPaused] = useState(false);
  const [position, setPosition] = useState(0);
  const [duration, setDuration] = useState(0);
  const [buffered, setBuffered] = useState(0);
  const [drawer, setDrawer] = useState(false);
  const [overlay, setOverlay] = useState<Overlay>("none");
  const [countdown, setCountdown] = useState(settings.autoplayCountdown);
  const [scrubbing, setScrubbing] = useState(false);
  const [seekTarget, setSeekTarget] = useState(0);

  const hideTimer = useRef<number | null>(null);
  const scrubTimer = useRef<number | null>(null);
  const seekHeldSince = useRef<number | null>(null);
  const pendingSeek = useRef(0);
  const resumeAsked = useRef(false);
  const startAt = useRef(requestedAt);

  const episodes = useMemo(
    () => [...(detail?.episodes ?? [])].sort((a, b) => a.number - b.number),
    [detail],
  );
  const episode = useMemo(
    () => episodes.find((ep) => ep.number === episodeNumber) ?? null,
    [episodes, episodeNumber],
  );
  const episodePath = requestedPath || episode?.path
    || episodePathFor(provider, slug, season, episodeNumber);

  const nextEp = useMemo(
    () => (episode ? nextEpisode(episode, episodes) : null),
    [episode, episodes],
  );
  const prevEp = useMemo(
    () => (episode ? previousEpisode(episode, episodes) : null),
    [episode, episodes],
  );

  const title = detail?.title ?? slug;
  const subtitle = `Staffel ${season} · Folge ${episodeNumber}`
    + (episode?.germanTitle ? ` · ${episode.germanTitle}` : "");

  // ---- Bedienung ein- und ausblenden -------------------------------------

  const showChrome = useCallback(() => {
    setChrome(true);
    if (hideTimer.current !== null) window.clearTimeout(hideTimer.current);
    hideTimer.current = window.setTimeout(
      () => setChrome(false),
      Math.max(2, settings.controlsTimeout) * 1000,
    );
  }, [settings.controlsTimeout]);

  const holdChrome = useCallback(() => {
    setChrome(true);
    if (hideTimer.current !== null) window.clearTimeout(hideTimer.current);
  }, []);

  useEffect(() => {
    showChrome();
    return () => {
      if (hideTimer.current !== null) window.clearTimeout(hideTimer.current);
    };
  }, [showChrome]);

  // Bei Pause und offenem Drawer bleibt die Bedienung stehen.
  useEffect(() => {
    if (paused || drawer || overlay !== "none") holdChrome();
    else showChrome();
  }, [paused, drawer, overlay, holdChrome, showChrome]);

  useEffect(() => keepAwake(phase === "playing" && !paused), [phase, paused]);

  // ---- Daten laden --------------------------------------------------------

  useEffect(() => {
    let cancelled = false;
    series(provider, slug, season).then(
      (value) => {
        if (!cancelled) setDetail(value);
      },
      (cause: unknown) => log("data", "Serie im Player nicht ladbar", (cause as Error)?.message),
    );
    return () => {
      cancelled = true;
    };
  }, [series, provider, slug, season]);

  useEffect(() => {
    let cancelled = false;
    setPhase("resolving");
    setStatusText("Folge wird geöffnet …");
    setInfo(null);
    setSource(null);
    setFailedHosters([]);
    watch(provider, episodePath).then(
      (value) => {
        if (cancelled) return;
        setInfo(value);
        const langs = availableLanguages(value.hosters);
        setLang((current) => (langs.includes(current) ? current : langs[0] ?? current));
      },
      (cause: unknown) => {
        if (cancelled) return;
        setPhase("error");
        setErrorText((cause as Error)?.message ?? "Folge nicht ladbar");
      },
    );
    return () => {
      cancelled = true;
    };
  }, [watch, provider, episodePath]);

  // ---- Auflösen -----------------------------------------------------------

  const resolveWith = useCallback(async (pick?: HosterOption, skip: string[] = []) => {
    if (!info) return;
    setPhase("resolving");
    setStatusText(pick ? `${pick.name} wird geöffnet …` : "Stream wird gesucht …");
    try {
      const resolved = await gateway.resolve({
        provider,
        episodePath,
        hosters: info.hosters,
        pick,
        preferredHoster: library.state.hosterPref,
        preferredLang: lang,
        skip,
      });
      log("resolver", "Stream", resolved.hoster, resolved.lang, resolved.kind);
      setSource(resolved);
      setPhase("playing");
    } catch (cause) {
      const message = cause instanceof NoriError
        ? cause.message
        : (cause as Error)?.message ?? "Kein Hoster lieferte einen Stream.";
      warn("resolver", message);
      setErrorText(message);
      setPhase("error");
    }
  }, [gateway, info, provider, episodePath, lang, library.state.hosterPref]);

  useEffect(() => {
    if (!info) return;
    void resolveWith(undefined, failedHosters);
    // Nur bei neuen Hosterdaten oder gewechselter Sprache neu auflösen — nicht
    // bei jedem Rendern.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [info, lang]);

  // ---- Wiedergabe anhängen -----------------------------------------------

  useEffect(() => {
    const video = videoRef.current;
    if (!video || !source || phase !== "playing") return;
    const url = gateway.playbackURL(source);
    const playback = attachPlayback({
      video,
      url,
      kind: source.kind,
      startAt: startAt.current,
      onEngine: (engine) => log("playback", "Engine", engine),
      onFatal: (message) => {
        setErrorText(message);
        setPhase("error");
      },
    });
    playbackRef.current = playback;
    return () => {
      playback.destroy();
      playbackRef.current = null;
    };
  }, [source, phase, gateway]);

  // Restlos abbauen, wenn die Seite verlassen wird — auch wenn der Effekt oben
  // durch einen Fehler nie lief.
  useEffect(() => () => {
    playbackRef.current?.destroy();
    playbackRef.current = null;
  }, []);

  // ---- Fortschritt --------------------------------------------------------

  const saveProgress = useCallback((positionSec: number, durationSec: number, completed?: boolean) => {
    if (durationSec <= 0) return;
    library.saveProgress({
      slug,
      title,
      season,
      episode: episodeNumber,
      episodePath,
      germanTitle: episode?.germanTitle ?? "",
      englishTitle: episode?.englishTitle ?? "",
      positionSec,
      durationSec,
      updatedAt: Date.now(),
      lang,
      completed,
      provider,
    });
  }, [library, slug, title, season, episodeNumber, episodePath, episode, lang, provider]);

  useEffect(() => {
    if (phase !== "playing") return;
    const timer = window.setInterval(() => {
      const video = videoRef.current;
      if (!video || video.paused || !Number.isFinite(video.duration)) return;
      saveProgress(video.currentTime, video.duration);
    }, 5000);
    return () => window.clearInterval(timer);
  }, [phase, saveProgress]);

  // Beim Verlassen den letzten Stand sichern; sonst fehlen die letzten
  // Sekunden vor dem Zurückgehen.
  useEffect(() => () => {
    const video = videoRef.current;
    if (video && Number.isFinite(video.duration) && video.duration > 0 && video.currentTime > 0) {
      saveProgress(video.currentTime, video.duration);
    }
  }, [saveProgress]);

  // ---- Videoereignisse ----------------------------------------------------

  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    const onTime = () => {
      setPosition(video.currentTime);
      if (video.buffered.length > 0) {
        setBuffered(video.buffered.end(video.buffered.length - 1));
      }
    };
    const onMeta = () => {
      setDuration(Number.isFinite(video.duration) ? video.duration : 0);
      video.playbackRate = library.state.playbackSpeed;
      // Resume-Frage nur, wenn nicht schon eine Position mitgegeben wurde.
      if (!resumeAsked.current && startAt.current < 8) {
        resumeAsked.current = true;
        const stored = library.progressFor(episodePath, provider);
        const at = library.state.resumeEnabled ? resumePosition(stored) : 0;
        if (at >= 8) {
          startAt.current = at;
          setOverlay("resume");
          video.pause();
        }
      }
    };
    const onPlay = () => setPaused(false);
    const onPause = () => setPaused(true);
    const onEnded = () => {
      saveProgress(video.duration, video.duration, true);
      if (library.state.autoplayNext && nextEp) {
        setCountdown(settings.autoplayCountdown);
        setOverlay("next");
      } else {
        navigate(-1);
      }
    };
    video.addEventListener("timeupdate", onTime);
    video.addEventListener("progress", onTime);
    video.addEventListener("loadedmetadata", onMeta);
    video.addEventListener("play", onPlay);
    video.addEventListener("pause", onPause);
    video.addEventListener("ended", onEnded);
    return () => {
      video.removeEventListener("timeupdate", onTime);
      video.removeEventListener("progress", onTime);
      video.removeEventListener("loadedmetadata", onMeta);
      video.removeEventListener("play", onPlay);
      video.removeEventListener("pause", onPause);
      video.removeEventListener("ended", onEnded);
    };
  }, [library, episodePath, provider, saveProgress, nextEp, navigate, settings.autoplayCountdown]);

  // ---- Countdown ----------------------------------------------------------

  const goToEpisode = useCallback((target: Episode) => {
    playbackRef.current?.destroy();
    playbackRef.current = null;
    resumeAsked.current = false;
    startAt.current = 0;
    setOverlay("none");
    setDrawer(false);
    setPosition(0);
    setDuration(0);
    setSearch({
      season,
      episode: String(target.number),
      path: target.path,
      at: "0",
    }, { replace: true });
  }, [season, setSearch]);

  useEffect(() => {
    if (overlay !== "next" || !nextEp) return;
    const timer = window.setInterval(() => {
      setCountdown((value) => {
        if (value <= 1) {
          window.clearInterval(timer);
          goToEpisode(nextEp);
          return 0;
        }
        return value - 1;
      });
    }, 1000);
    return () => window.clearInterval(timer);
  }, [overlay, nextEp, goToEpisode]);

  // ---- Steuerung ----------------------------------------------------------

  const togglePlay = useCallback(() => {
    const video = videoRef.current;
    if (!video) return;
    if (video.paused) void video.play().catch(() => undefined);
    else video.pause();
    showChrome();
  }, [showChrome]);

  const commitSeek = useCallback(() => {
    const video = videoRef.current;
    if (!video) return;
    const target = Math.min(Math.max(0, pendingSeek.current), video.duration || 0);
    video.currentTime = target;
    pendingSeek.current = 0;
    setScrubbing(false);
    seekHeldSince.current = null;
  }, []);

  const seekBy = useCallback((delta: number) => {
    const video = videoRef.current;
    if (!video || !Number.isFinite(video.duration)) return;
    const base = scrubbing ? seekTarget : video.currentTime;
    const target = Math.min(Math.max(0, base + delta), video.duration);
    pendingSeek.current = target;
    setSeekTarget(target);
    setScrubbing(true);
    showChrome();
    // Gesammelt springen: bei gehaltener Taste sonst ein Sprung je Wiederholung,
    // und der Fernseher puffert bei jedem davon neu.
    if (scrubTimer.current !== null) window.clearTimeout(scrubTimer.current);
    scrubTimer.current = window.setTimeout(commitSeek, 420);
  }, [scrubbing, seekTarget, showChrome, commitSeek]);

  const switchHoster = useCallback((option: HosterOption) => {
    const video = videoRef.current;
    startAt.current = video && Number.isFinite(video.currentTime) ? video.currentTime : startAt.current;
    log("hoster", "Wechsel auf", option.name, "bei", Math.round(startAt.current));
    library.setPreference({ hosterPref: option.name });
    setDrawer(false);
    setSource(null);
    void resolveWith(option);
  }, [library, resolveWith]);

  const switchLanguage = useCallback((next: string) => {
    const video = videoRef.current;
    startAt.current = video && Number.isFinite(video.currentTime) ? video.currentTime : startAt.current;
    log("hoster", "Sprachwechsel auf", next);
    library.setPreference({ langPref: next });
    setDrawer(false);
    setSource(null);
    setLang(next);
  }, [library]);

  const exitPlayer = useCallback(() => {
    playbackRef.current?.destroy();
    playbackRef.current = null;
    navigate(-1);
  }, [navigate]);

  // ---- Zurück-Reihenfolge -------------------------------------------------

  useBackHandler(() => {
    if (overlay === "next") {
      setOverlay("none");
      return true;
    }
    if (overlay === "resume") return true;
    if (drawer) {
      setDrawer(false);
      showChrome();
      return true;
    }
    if (chrome) {
      setChrome(false);
      if (hideTimer.current !== null) window.clearTimeout(hideTimer.current);
      return true;
    }
    exitPlayer();
    return true;
  });

  // ---- Fernbedienung ------------------------------------------------------

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (isBack(event)) return; // dafür ist der Zurück-Stapel zuständig
      if (overlay === "resume") return;

      const media = seekDirection(event);
      const arrow = arrowDirection(event);

      if (isPlay(event)) {
        event.preventDefault();
        void videoRef.current?.play().catch(() => undefined);
        showChrome();
        return;
      }
      if (isPause(event) || isStop(event)) {
        event.preventDefault();
        videoRef.current?.pause();
        if (isStop(event)) exitPlayer();
        else showChrome();
        return;
      }
      if (isPlayPause(event) && !drawer) {
        event.preventDefault();
        togglePlay();
        return;
      }

      if (media) {
        event.preventDefault();
        if (seekHeldSince.current === null) seekHeldSince.current = Date.now();
        const factor = seekMultiplier(Date.now() - seekHeldSince.current);
        seekBy(media * settings.seekStep * factor);
        return;
      }

      if (drawer || overlay !== "none") return;

      // Ohne sichtbare Bedienung steuern die Pfeiltasten die Wiedergabe selbst.
      if (!chrome && arrow) {
        event.preventDefault();
        if (arrow === "left" || arrow === "right") {
          if (seekHeldSince.current === null) seekHeldSince.current = Date.now();
          const factor = seekMultiplier(Date.now() - seekHeldSince.current);
          seekBy((arrow === "right" ? 1 : -1) * settings.seekStep * factor);
        } else if (arrow === "up") {
          setDrawer(true);
        } else {
          showChrome();
        }
        return;
      }

      if (chrome && arrow === "up") {
        event.preventDefault();
        setDrawer(true);
        return;
      }

      if (!chrome && isEnter(event)) {
        event.preventDefault();
        togglePlay();
        return;
      }

      // Jede andere Taste holt die Bedienung zurück.
      showChrome();
    };

    const onKeyUp = (event: KeyboardEvent) => {
      if (seekDirection(event) || arrowDirection(event) === "left" || arrowDirection(event) === "right") {
        seekHeldSince.current = null;
      }
    };

    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("keyup", onKeyUp);
    return () => {
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("keyup", onKeyUp);
    };
  }, [chrome, drawer, overlay, seekBy, settings.seekStep, showChrome, togglePlay, exitPlayer]);

  const resumeRef = useAutoFocus(overlay === "resume");
  const nextRef = useAutoFocus(overlay === "next");
  const errorRef = useAutoFocus(phase === "error");

  const remainingHosters = useMemo(() => {
    if (!info) return [] as HosterOption[];
    return orderHosters(
      info.hosters.filter((h) => h.lang.toLowerCase() === lang.toLowerCase()),
      library.state.hosterPref,
    ).filter((h) => !failedHosters.includes(`${h.name}|${h.lang}`));
  }, [info, lang, library.state.hosterPref, failedHosters]);

  return (
    <div className="player-page">
      <video
        ref={videoRef}
        className="player-video"
        playsInline
        autoPlay
        preload="auto"
      />

      {phase === "resolving" ? (
        <div className="player-status" role="status">
          <span className="spinner" aria-hidden="true" />
          <strong>{statusText}</strong>
          <small>{title} · {subtitle}</small>
        </div>
      ) : null}

      {phase === "error" ? (
        <SpotArea className="player-error" spotlightId="player-error" restrict="self-only">
          <div ref={errorRef}>
            <i className="player-error-mark"><Icon name="warning" /></i>
            <h2>Der Stream lässt sich nicht öffnen</h2>
            <p>{errorText}</p>
            <div className="button-row">
              {remainingHosters.length > 0 ? (
                <SpotButton
                  className="primary"
                  focusKey="error-next-hoster"
                  onClick={() => {
                    const failed = source ? [`${source.hoster}|${source.lang}`] : [];
                    setFailedHosters((list) => [...list, ...failed]);
                    void resolveWith(remainingHosters[0]);
                  }}
                >
                  Anderen Hoster versuchen ({remainingHosters[0].name})
                </SpotButton>
              ) : null}
              <SpotButton focusKey="error-retry" onClick={() => void resolveWith()}>
                Erneut versuchen
              </SpotButton>
              <SpotButton focusKey="error-drawer" onClick={() => { setPhase("resolving"); setDrawer(true); }}>
                Sprache &amp; Hoster
              </SpotButton>
              <SpotButton focusKey="error-exit" onClick={exitPlayer}>
                Zurück
              </SpotButton>
            </div>
          </div>
        </SpotArea>
      ) : null}

      {overlay === "resume" ? (
        <SpotArea className="player-overlay" spotlightId="player-resume" restrict="self-only">
          <div ref={resumeRef} className="overlay-card">
            <span className="eyebrow">Weiterschauen</span>
            <h2>Fortsetzen bei {clock(startAt.current)}?</h2>
            <div className="button-row">
              <SpotButton
                className="primary"
                focusKey="resume-yes"
                onClick={() => {
                  const video = videoRef.current;
                  if (video) {
                    video.currentTime = startAt.current;
                    void video.play().catch(() => undefined);
                  }
                  setOverlay("none");
                }}
              >
                <Icon name="play" />
                Fortsetzen
              </SpotButton>
              <SpotButton
                focusKey="resume-no"
                onClick={() => {
                  const video = videoRef.current;
                  if (video) {
                    video.currentTime = 0;
                    void video.play().catch(() => undefined);
                  }
                  startAt.current = 0;
                  setOverlay("none");
                }}
              >
                Von vorne
              </SpotButton>
            </div>
          </div>
        </SpotArea>
      ) : null}

      {overlay === "next" && nextEp ? (
        <SpotArea className="player-overlay next" spotlightId="player-next" restrict="self-only">
          <div ref={nextRef} className="overlay-card">
            <span className="eyebrow">Nächste Folge</span>
            <h2>Folge {nextEp.number}</h2>
            <p>{nextEp.germanTitle || nextEp.englishTitle}</p>
            <small>Startet in {countdown} Sekunden</small>
            <div className="button-row">
              <SpotButton className="primary" focusKey="next-now" onClick={() => goToEpisode(nextEp)}>
                <Icon name="play" />
                Jetzt starten
              </SpotButton>
              <SpotButton focusKey="next-cancel" onClick={() => { setOverlay("none"); exitPlayer(); }}>
                Abbrechen
              </SpotButton>
            </div>
          </div>
        </SpotArea>
      ) : null}

      <PlayerControls
        visible={chrome && phase === "playing" && overlay === "none" && !drawer}
        title={title}
        subtitle={subtitle}
        paused={paused}
        position={position}
        duration={duration}
        buffered={buffered}
        scrubbing={scrubbing}
        seekTarget={seekTarget}
        seekStep={settings.seekStep}
        hosterLabel={source ? `${source.hoster} · ${source.lang}` : lang}
        previous={prevEp}
        next={nextEp}
        onTogglePlay={togglePlay}
        onSeek={seekBy}
        onPrevious={() => prevEp && goToEpisode(prevEp)}
        onNext={() => nextEp && goToEpisode(nextEp)}
        onOpenDrawer={() => setDrawer(true)}
        onExit={exitPlayer}
      />

      <PlayerDrawer
        open={drawer}
        languages={info ? availableLanguages(info.hosters) : []}
        activeLang={lang}
        hosters={info?.hosters ?? []}
        activeHoster={source?.hoster ?? null}
        seasons={detail?.seasons ?? []}
        activeSeason={season}
        episodes={episodes}
        activeEpisode={episodeNumber}
        onLanguage={switchLanguage}
        onHoster={switchHoster}
        onSeason={(id) => {
          setDrawer(false);
          navigate(`/titel/${provider}/${encodeURIComponent(slug)}?season=${encodeURIComponent(id)}`);
        }}
        onEpisode={goToEpisode}
        onClose={() => setDrawer(false)}
      />
    </div>
  );
}

function clock(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const r = s % 60;
  const pad = (n: number) => String(n).padStart(2, "0");
  return h > 0 ? `${h}:${pad(m)}:${pad(r)}` : `${m}:${pad(r)}`;
}
