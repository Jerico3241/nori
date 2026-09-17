// Der Player.
//
// ## Was er vom Fernseher übernimmt
//
// Das Auflösen des Hosters, die Reihenfolge der Hoster, die Wiedergabe-
// anbindung (`attachPlayback`, nativ oder hls.js) und die Fortschrittsregeln
// (90 % gilt als gesehen, ab 8 Sekunden wird fortgesetzt) — alles aus
// `@nori/core` und `@nori/app`. Eine zweite Wiedergabelogik gäbe es sonst, und
// sie liefe auseinander.
//
// ## Was hier anders ist
//
// **Die Bedienung.** Ein Fernseher hat vier Richtungstasten und OK. Ein
// Rechner hat Maus, Tastatur und die Gewohnheiten von zwanzig Jahren
// Videoplayern:
//
//     Leertaste / K     Wiedergabe und Pause
//     ← →               springen
//     ↑ ↓               Lautstärke
//     F / Doppelklick   Vollbild
//     M                 stumm
//     N                 nächste Folge
//     Escape            Vollbild verlassen, sonst zurück
//
// **Die Bedienleiste** blendet sich nach Ruhe aus und kommt bei jeder
// Mausbewegung zurück. Auf dem Fernseher hängt sie an Tastendrücken — hier
// wäre das falsch, weil die Maus der Regelfall ist.
//
// **`Referer`.** Etliche Hoster liefern ohne diese Kopfzeile nichts aus. Ein
// `<video src>` kann sie nicht setzen; der Hauptprozess schon, und
// `ShellGateway.playbackURL` meldet sie dort an, bevor die Adresse gesetzt
// wird. Deshalb läuft auf Windows, was im Browser scheitern würde.
//
// **Hardwarebeschleunigung.** Electron liefert Chromium mit H.264 und AAC und
// nutzt die Decoder von Windows. Nori muss dafür nichts tun — außer dem
// `<video>` nicht im Weg zu stehen: keine Filter, keine Transformationen, kein
// `border-radius` darauf.

import {
  Icon, attachPlayback, log, useData, useLibrary, useSettings, warn, type Playback,
} from "@nori/app";
import {
  NoriError, availableLanguages, emptyRecovery, episodePathFor, formatClock, hosterRank,
  nextEpisode, noteSourceFailure, noteSourceSuccess, noteSourceSwitch, planRecovery,
  previousEpisode, recoveryForEpisode, remainingSources, resumePosition,
  type CatalogProvider, type Episode, type HosterOption, type PlaySource, type SeriesDetail,
  type WatchInfo,
} from "@nori/core";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useParams, useSearchParams } from "react-router-dom";

import { bridge } from "../bridge";

type Phase = "resolving" | "playing" | "error";

/** Unter acht Sekunden wird kein Fortschritt gemerkt — das ist die Contract-Regel. */
const MIN_SAVED_POSITION = 8;
/** Wie oft der Stand geschrieben wird, solange etwas läuft. */
const SAVE_INTERVAL_MS = 5000;

function isProvider(value: string | undefined): value is CatalogProvider {
  return value === "aniworld" || value === "serienstream";
}

export function PlayerPage() {
  const params = useParams<{ provider: string; slug: string }>();
  const [search] = useSearchParams();
  const navigate = useNavigate();
  const { gateway, watch, series } = useData();
  const library = useLibrary();
  const { settings } = useSettings();

  const provider: CatalogProvider = isProvider(params.provider) ? params.provider : "aniworld";
  const slug = decodeURIComponent(params.slug ?? "");
  const season = search.get("season") ?? "1";
  const episodeNumber = Number(search.get("episode") ?? "1");
  const episodePath = search.get("path") || episodePathFor(provider, slug, season, episodeNumber);
  const startAt = useRef(Number(search.get("at") ?? "0"));

  const video = useRef<HTMLVideoElement>(null);
  const playback = useRef<Playback | null>(null);
  const [detail, setDetail] = useState<SeriesDetail | null>(null);
  const [info, setInfo] = useState<WatchInfo | null>(null);
  const [source, setSource] = useState<PlaySource | null>(null);
  const [phase, setPhase] = useState<Phase>("resolving");
  const [statusText, setStatusText] = useState("Folge wird geöffnet …");
  const [errorText, setErrorText] = useState("");
  /**
   * Welche Quellen für diese Folge schon gescheitert sind und wie oft
   * gewechselt wurde. Die Regeln stehen im Kern (`planRecovery`) und gelten
   * damit auf jedem Nori-Client gleich.
   */
  const [recovery, setRecovery] = useState(() => emptyRecovery());
  /** Sekunden bis zur nächsten Folge. `null` heißt: kein Countdown. */
  const [countdown, setCountdown] = useState<number | null>(null);
  const [lang, setLang] = useState(library.state.langPref);

  const [playing, setPlaying] = useState(false);
  const [position, setPosition] = useState(0);
  const [duration, setDuration] = useState(0);
  const [buffered, setBuffered] = useState(0);
  const [volume, setVolume] = useState(1);
  const [muted, setMuted] = useState(false);
  const [fullscreen, setFullscreen] = useState(false);
  const [chromeVisible, setChromeVisible] = useState(true);
  const [panelOpen, setPanelOpen] = useState(false);
  const hideTimer = useRef<number | null>(null);

  const episodes = useMemo(() => detail?.episodes ?? [], [detail]);
  const episode = useMemo(
    () => episodes.find((entry) => entry.number === episodeNumber) ?? null,
    [episodes, episodeNumber],
  );
  const title = detail?.title ?? library.state.titles[slug] ?? slug;
  const nextEp = useMemo(() => (episode ? nextEpisode(episode, episodes) : null), [episode, episodes]);
  const prevEp = useMemo(() => (episode ? previousEpisode(episode, episodes) : null), [episode, episodes]);

  // ---- Daten --------------------------------------------------------------

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
    setCountdown(null);
    setRecovery((state) => recoveryForEpisode(state, `${provider}|${episodePath}`));
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
      setRecovery((state) => noteSourceSuccess(state));
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
    void resolveWith(undefined, recovery.failed);
    // Nur bei neuen Hosterdaten oder gewechselter Sprache neu auflösen.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [info, lang]);

  /**
   * Ein Stream ist mitten in der Wiedergabe abgebrochen.
   *
   * Nicht einfach den Fehler stehen lassen: eine Schutzseite oder eine
   * abgelaufene Adresse ist beim nächsten Hoster regelmäßig nicht da. Wie weit
   * das gehen darf, entscheidet der Kern (`planRecovery`) — mit Budget, damit
   * es nicht in eine Schleife läuft.
   */
  const recoverFrom = useCallback((message: string) => {
    const current = source ? { hoster: source.hoster, lang: source.lang } : null;
    const failed = noteSourceFailure(recovery, current);
    const step = planRecovery(failed, info?.hosters ?? [], current, library.state.hosterPref);

    if (step.kind === "switch") {
      const advanced = noteSourceSwitch(failed);
      setRecovery(advanced);
      warn("playback", message, "— weiter mit", step.option.name);
      void resolveWith(step.option, advanced.failed);
      return;
    }
    if (step.kind === "retry") {
      setRecovery(failed);
      warn("playback", message, "— noch einmal");
      void resolveWith(undefined, failed.failed);
      return;
    }
    setRecovery(failed);
    setErrorText([message, step.reason].filter(Boolean).join("\n"));
    setPhase("error");
  }, [source, recovery, info, library.state.hosterPref, resolveWith]);

  // ---- Wiedergabe ---------------------------------------------------------

  useEffect(() => {
    const node = video.current;
    if (!node || !source || phase !== "playing") return undefined;
    const url = gateway.playbackURL(source);
    const attached = attachPlayback({
      video: node,
      url,
      kind: source.kind,
      startAt: startAt.current,
      onEngine: (engine) => log("playback", "Engine", engine),
      onFatal: (message) => recoverFrom(message),
    });
    playback.current = attached;
    void node.play().catch(() => undefined);
    return () => {
      attached.destroy();
      playback.current = null;
    };
  }, [source, phase, gateway]);

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

  /** Der aktuelle Stand für alles, was außerhalb des Renderns läuft. */
  const latest = useRef({ saveProgress, nextEp, settings, library });
  latest.current = { saveProgress, nextEp, settings, library };

  const openEpisode = useCallback((target: Episode, at = 0) => {
    navigate(
      `/player/${provider}/${encodeURIComponent(slug)}`
      + `?season=${encodeURIComponent(season)}&episode=${target.number}`
      + `&path=${encodeURIComponent(target.path)}&at=${Math.floor(at)}`,
      { replace: true },
    );
    startAt.current = at;
  }, [navigate, provider, slug, season]);

  /**
   * Der Countdown zur nächsten Folge.
   *
   * Eigener Effekt, nicht in der Aufgabe, die ihn gestartet hat: ein Wechsel
   * der Folge räumt diese Ansicht ab, und ein Timer darin liefe ins Leere.
   * Abgebrochen wird er durch jeden Druck auf „Abbrechen" — und dadurch, dass
   * `countdown` beim Öffnen einer Folge auf `null` zurückfällt.
   */
  useEffect(() => {
    if (countdown === null) return undefined;
    if (countdown <= 0) {
      const next = latest.current.nextEp;
      setCountdown(null);
      if (next) openEpisode(next, 0);
      return undefined;
    }
    const timer = window.setTimeout(() => setCountdown((value) => (value === null ? null : value - 1)), 1000);
    return () => window.clearTimeout(timer);
  }, [countdown, openEpisode]);

  useEffect(() => {
    const node = video.current;
    if (!node) return undefined;

    const onTime = () => {
      setPosition(node.currentTime);
      if (node.buffered.length > 0) setBuffered(node.buffered.end(node.buffered.length - 1));
    };
    const onMeta = () => setDuration(node.duration || 0);
    const onPlay = () => setPlaying(true);
    const onPause = () => setPlaying(false);
    const onVolume = () => {
      setVolume(node.volume);
      setMuted(node.muted);
    };
    const onEnded = () => {
      const { saveProgress: save, nextEp: next, settings: device } = latest.current;
      save(node.duration || 0, node.duration || 0, true);
      if (!latest.current.library.state.autoplayNext || !next) return;
      // Mit Countdown statt sofortigem Sprung — wie auf iPhone, Mac und
      // Fernseher. Die Länge kommt aus den Geräteeinstellungen, deren Vorgabe
      // im Kern steht (`AUTOPLAY_COUNTDOWN_SEC`). Bei 0 geht es sofort weiter.
      if (device.autoplayCountdown <= 0) {
        openEpisode(next, 0);
        return;
      }
      setCountdown(device.autoplayCountdown);
    };
    node.addEventListener("timeupdate", onTime);
    node.addEventListener("progress", onTime);
    node.addEventListener("loadedmetadata", onMeta);
    node.addEventListener("durationchange", onMeta);
    node.addEventListener("play", onPlay);
    node.addEventListener("pause", onPause);
    node.addEventListener("volumechange", onVolume);
    node.addEventListener("ended", onEnded);

    // Regelmäßig schreiben, damit ein Absturz nicht die ganze Folge kostet.
    const timer = window.setInterval(() => {
      if (node.paused) return;
      const at = node.currentTime;
      const total = node.duration || 0;
      if (total > 0 && at >= MIN_SAVED_POSITION) latest.current.saveProgress(at, total);
    }, SAVE_INTERVAL_MS);

    return () => {
      node.removeEventListener("timeupdate", onTime);
      node.removeEventListener("progress", onTime);
      node.removeEventListener("loadedmetadata", onMeta);
      node.removeEventListener("durationchange", onMeta);
      node.removeEventListener("play", onPlay);
      node.removeEventListener("pause", onPause);
      node.removeEventListener("volumechange", onVolume);
      node.removeEventListener("ended", onEnded);
      window.clearInterval(timer);
      const at = node.currentTime;
      const total = node.duration || 0;
      if (total > 0 && at >= MIN_SAVED_POSITION) latest.current.saveProgress(at, total);
    };
  }, [openEpisode]);

  // ---- Bedienung ----------------------------------------------------------

  const showChrome = useCallback(() => {
    setChromeVisible(true);
    if (hideTimer.current) window.clearTimeout(hideTimer.current);
    hideTimer.current = window.setTimeout(() => {
      if (!video.current?.paused) setChromeVisible(false);
    }, Math.max(2, settings.controlsTimeout) * 1000);
  }, [settings.controlsTimeout]);

  useEffect(() => {
    showChrome();
    return () => {
      if (hideTimer.current) window.clearTimeout(hideTimer.current);
    };
  }, [showChrome]);

  const togglePlay = useCallback(() => {
    const node = video.current;
    if (!node) return;
    if (node.paused) void node.play().catch(() => undefined);
    else node.pause();
    showChrome();
  }, [showChrome]);

  const seekBy = useCallback((seconds: number) => {
    const node = video.current;
    if (!node || !Number.isFinite(node.duration)) return;
    node.currentTime = Math.max(0, Math.min(node.duration, node.currentTime + seconds));
    showChrome();
  }, [showChrome]);

  const toggleFullscreen = useCallback(() => {
    const api = bridge();
    if (api) void api.window.toggleFullscreen().then(setFullscreen);
    else if (document.fullscreenElement) void document.exitFullscreen().then(() => setFullscreen(false));
    else void document.documentElement.requestFullscreen().then(() => setFullscreen(true));
  }, []);

  useEffect(() => {
    const api = bridge();
    if (!api) return undefined;
    void api.window.isFullscreen().then(setFullscreen);
    return api.window.onFullscreen(setFullscreen);
  }, []);

  const leave = useCallback(() => {
    const api = bridge();
    if (fullscreen && api) {
      void api.window.exitFullscreen();
      return;
    }
    navigate(-1);
  }, [fullscreen, navigate]);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.target instanceof HTMLInputElement || event.target instanceof HTMLSelectElement) return;
      const step = Math.max(1, settings.seekStep);
      const node = video.current;
      switch (event.key) {
        case " ":
        case "k":
        case "K":
          event.preventDefault();
          togglePlay();
          break;
        case "ArrowLeft": event.preventDefault(); seekBy(-step); break;
        case "ArrowRight": event.preventDefault(); seekBy(step); break;
        case "ArrowUp":
          event.preventDefault();
          if (node) node.volume = Math.min(1, node.volume + 0.05);
          showChrome();
          break;
        case "ArrowDown":
          event.preventDefault();
          if (node) node.volume = Math.max(0, node.volume - 0.05);
          showChrome();
          break;
        case "f":
        case "F":
          event.preventDefault();
          toggleFullscreen();
          break;
        case "m":
        case "M":
          event.preventDefault();
          if (node) node.muted = !node.muted;
          showChrome();
          break;
        case "n":
        case "N":
          if (nextEp) {
            event.preventDefault();
            openEpisode(nextEp, 0);
          }
          break;
        case "Escape":
          event.preventDefault();
          leave();
          break;
        default:
          break;
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [togglePlay, seekBy, toggleFullscreen, showChrome, nextEp, openEpisode, leave, settings.seekStep]);

  // ---- Hoster -------------------------------------------------------------

  const languages = useMemo(() => (info ? availableLanguages(info.hosters) : []), [info]);
  const hosters = useMemo(() => (info?.hosters ?? [])
    .filter((option) => option.lang.toLowerCase() === lang.toLowerCase())
    .sort((a, b) => hosterRank(a.name) - hosterRank(b.name)), [info, lang]);

  /** Die Quellen, die für diese Folge noch übrig sind — ohne die gescheiterten. */
  const remainingHosters = useMemo(
    () => (info ? remainingSources(recovery, info.hosters, lang, library.state.hosterPref) : []),
    [info, lang, library.state.hosterPref, recovery],
  );

  const tryNextHoster = useCallback(() => {
    const next = remainingHosters[0];
    if (!next) return;
    const advanced = noteSourceSwitch(
      source ? noteSourceFailure(recovery, { hoster: source.hoster, lang: source.lang }) : recovery,
    );
    setRecovery(advanced);
    void resolveWith(next, advanced.failed);
  }, [remainingHosters, recovery, resolveWith, source]);

  const percent = duration > 0 ? (position / duration) * 100 : 0;
  const bufferPercent = duration > 0 ? (buffered / duration) * 100 : 0;
  const episodeLabel = episode?.germanTitle || episode?.englishTitle || `Folge ${episodeNumber}`;

  return (
    <div
      className={`player${chromeVisible || !playing ? " chrome" : ""}`}
      onMouseMove={showChrome}
      onDoubleClick={toggleFullscreen}
    >
      <video
        ref={video}
        className="player-video"
        playsInline
        autoPlay
        onClick={togglePlay}
      />

      {countdown !== null && nextEp ? (
        <div className="player-next" role="status">
          <span className="eyebrow">Als Nächstes</span>
          <strong>{nextEp.number}. {nextEp.germanTitle || nextEp.englishTitle || `Folge ${nextEp.number}`}</strong>
          <small>Startet in {countdown} {countdown === 1 ? "Sekunde" : "Sekunden"}</small>
          <div className="hero-actions">
            <button
              type="button"
              className="btn primary"
              onClick={() => { setCountdown(null); openEpisode(nextEp, 0); }}
            >
              <Icon name="play" /><span>Jetzt abspielen</span>
            </button>
            <button type="button" className="btn" onClick={() => setCountdown(null)}>
              <Icon name="close" /><span>Abbrechen</span>
            </button>
          </div>
        </div>
      ) : null}

      {phase !== "playing" ? (
        <div className="player-overlay">
          {phase === "error" ? (
            <div className="player-message" role="alert">
              <h2>Diese Folge lässt sich nicht abspielen</h2>
              <p>{errorText}</p>
              <div className="hero-actions">
                <button type="button" className="btn primary" onClick={() => void resolveWith()}>
                  <Icon name="refresh" /><span>Erneut versuchen</span>
                </button>
                {remainingHosters.length > 0 ? (
                  <button type="button" className="btn" onClick={tryNextHoster}>
                    <Icon name="layers" /><span>Anderer Hoster ({remainingHosters[0].name})</span>
                  </button>
                ) : null}
                <button type="button" className="btn" onClick={leave}>
                  <Icon name="back" /><span>Zurück</span>
                </button>
              </div>
            </div>
          ) : (
            <div className="player-message">
              <div className="spinner" aria-hidden="true" />
              <p>{statusText}</p>
            </div>
          )}
        </div>
      ) : null}

      <div className="player-top">
        <button type="button" className="btn ghost" onClick={leave} aria-label="Zurück">
          <Icon name="back" />
        </button>
        <div className="player-title">
          <b>{title}</b>
          <small>Staffel {season} · Folge {episodeNumber} · {episodeLabel}</small>
        </div>
        <button
          type="button"
          className="btn ghost"
          aria-label="Quelle und Folgen"
          onClick={() => setPanelOpen((value) => !value)}
        >
          <Icon name="layers" />
        </button>
      </div>

      <div className="player-bottom">
        <div
          className="seekbar"
          role="slider"
          tabIndex={0}
          aria-label="Position"
          aria-valuemin={0}
          aria-valuemax={Math.round(duration)}
          aria-valuenow={Math.round(position)}
          onClick={(event) => {
            const node = video.current;
            if (!node || !Number.isFinite(node.duration)) return;
            const box = event.currentTarget.getBoundingClientRect();
            node.currentTime = ((event.clientX - box.left) / box.width) * node.duration;
          }}
        >
          <span className="seek-buffer" style={{ width: `${bufferPercent}%` }} />
          <span className="seek-fill" style={{ width: `${percent}%` }} />
          <span className="seek-knob" style={{ left: `${percent}%` }} />
        </div>

        <div className="player-controls">
          <button type="button" className="btn ghost" onClick={() => seekBy(-settings.seekStep)} aria-label="Zurückspulen">
            <Icon name="rewind" />
          </button>
          <button type="button" className="btn ghost big" onClick={togglePlay} aria-label={playing ? "Pause" : "Abspielen"}>
            <Icon name={playing ? "pause" : "play"} />
          </button>
          <button type="button" className="btn ghost" onClick={() => seekBy(settings.seekStep)} aria-label="Vorspulen">
            <Icon name="forward" />
          </button>
          <button
            type="button"
            className="btn ghost"
            disabled={!prevEp}
            onClick={() => prevEp && openEpisode(prevEp, 0)}
            aria-label="Vorherige Folge"
          >
            <Icon name="previous" />
          </button>
          <button
            type="button"
            className="btn ghost"
            disabled={!nextEp}
            onClick={() => nextEp && openEpisode(nextEp, 0)}
            aria-label="Nächste Folge"
          >
            <Icon name="next" />
          </button>

          <span className="player-time">{formatClock(position)} / {formatClock(duration)}</span>

          <div className="player-volume">
            <button
              type="button"
              className="btn ghost"
              onClick={() => {
                const node = video.current;
                if (node) node.muted = !node.muted;
              }}
              aria-label={muted ? "Ton an" : "Stumm"}
            >
              <Icon name={muted || volume === 0 ? "close" : "pulse"} />
            </button>
            <input
              type="range"
              min={0}
              max={1}
              step={0.02}
              value={muted ? 0 : volume}
              aria-label="Lautstärke"
              onChange={(event) => {
                const node = video.current;
                if (!node) return;
                node.volume = Number(event.target.value);
                node.muted = Number(event.target.value) === 0;
              }}
            />
          </div>

          <button type="button" className="btn ghost" onClick={toggleFullscreen} aria-label="Vollbild">
            <Icon name={fullscreen ? "close" : "grid"} />
          </button>
        </div>
      </div>

      {panelOpen ? (
        <aside className="player-panel" aria-label="Quelle und Folgen">
          <div className="card-panel">
            <h3>Sprache</h3>
            <div className="chips">
              {languages.map((entry) => (
                <button
                  key={entry}
                  type="button"
                  className={`chip${entry.toLowerCase() === lang.toLowerCase() ? " active" : ""}`}
                  onClick={() => setLang(entry)}
                >
                  {entry}
                </button>
              ))}
            </div>
            <h3>Hoster</h3>
            <div className="chips">
              {hosters.map((option) => (
                <button
                  key={`${option.name}|${option.langKey}`}
                  type="button"
                  className={`chip${source?.hoster === option.name ? " active" : ""}`}
                  onClick={() => {
                    setPanelOpen(false);
                    void resolveWith(option);
                  }}
                >
                  {option.name}
                </button>
              ))}
            </div>
          </div>
          <div className="card-panel">
            <h3>Folgen</h3>
            {episodes.map((entry) => {
              const progress = library.progressForEpisode(slug, season, entry.number, entry.path, provider);
              return (
                <button
                  key={entry.path || entry.number}
                  type="button"
                  className="row"
                  onClick={() => {
                    setPanelOpen(false);
                    openEpisode(entry, library.state.resumeEnabled ? resumePosition(progress) : 0);
                  }}
                >
                  <span className="row-copy">
                    <b>{entry.number}. {entry.germanTitle || entry.englishTitle || `Folge ${entry.number}`}</b>
                  </span>
                  <span className="row-value">
                    {entry.number === episodeNumber ? <span className="badge ok">läuft</span> : null}
                  </span>
                </button>
              );
            })}
          </div>
        </aside>
      ) : null}
    </div>
  );
}
