import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { b as useNavigate, v as Link } from "../_libs/@tanstack/react-router+[...].mjs";
import { i as require_jsx_runtime, t as useQuery } from "../_libs/react+tanstack__react-query.mjs";
import { i as kindFromProvider, o as providerFromPath, s as useProvider } from "./provider-B-pxa-h2.mjs";
import { t as cn } from "./cn-Ccejyh36.mjs";
import { C as Gauge, D as Check, E as ChevronLeft, T as ChevronRight, _ as Minimize, c as SkipBack, f as RotateCw, g as Pause, h as PictureInPicture2, k as ArrowLeft, m as Play, n as VolumeX, r as Volume2, s as SkipForward, v as Maximize, y as LoaderCircle } from "../_libs/lucide-react.mjs";
import { B as watchRatio, F as progressForSlug, I as resumePosition, N as progressForEpisode, P as progressForPath, R as shouldPersistProgress, _ as recordProgress, j as isEpisodeComplete, k as formatClock, m as hintProviderForSlug, n as Route$6, z as useLibrary } from "./router-DDQw7P_P.mjs";
import { d as useCover, l as requestCover, o as fetchWatch, u as resolveBestPlay } from "./cover-prefetch-Dz9cGrY_.mjs";
import { t as fetchSeriesSmart } from "./series-query-ctGR06bO.mjs";
import { t as CoverToneRoot } from "./cover-tone-C-t57wR4.mjs";
import { t as Button } from "./button-6GLc1whh.mjs";
import { a as pickLang, i as pickHoster, o as usePlayback, r as langDisplay } from "./playback-CYrpmXej.mjs";
import { t as Hls } from "../_libs/hls.js.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/watch._slug-DK9J0JWY.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
function WatchPlayer({ ctx, onPrev, onNext, hasPrev, hasNext }) {
	const { path, germanTitle, englishTitle } = ctx;
	const langPref = usePlayback((s) => s.langPref);
	const hosterPref = usePlayback((s) => s.hosterPref);
	const autoplayNext = usePlayback((s) => s.autoplayNext);
	const provider = useProvider((s) => s.provider);
	const watchQuery = useQuery({
		queryKey: [
			"watch",
			provider,
			path
		],
		queryFn: () => fetchWatch({ data: {
			path,
			provider
		} }),
		staleTime: 6e5
	});
	const hosters = watchQuery.data?.hosters ?? [];
	const langs = (0, import_react.useMemo)(() => unique(hosters.map((h) => h.lang)), [hosters]);
	const [lang, setLang] = (0, import_react.useState)(langPref);
	const [hosterName, setHosterName] = (0, import_react.useState)(hosterPref);
	(0, import_react.useEffect)(() => {
		if (langs.length === 0) return;
		setLang((cur) => langs.includes(cur) ? cur : pickLang(langs, langPref));
	}, [langs, langPref]);
	const availableHosters = hosters.filter((h) => h.lang === lang);
	const availableKey = availableHosters.map((h) => h.redirectPath).join(",");
	const [activeHoster, setActiveHoster] = (0, import_react.useState)("");
	const [source, setSource] = (0, import_react.useState)();
	const [playError, setPlayError] = (0, import_react.useState)(null);
	const [resolving, setResolving] = (0, import_react.useState)(false);
	const [nextIn, setNextIn] = (0, import_react.useState)(null);
	(0, import_react.useEffect)(() => {
		if (availableHosters.length === 0) return;
		setHosterName((cur) => availableHosters.some((h) => h.name === cur) ? cur : pickHoster(availableHosters.map((h) => h.name), hosterPref));
	}, [availableKey, hosterPref]);
	async function loadStream(preferred, fresh = false) {
		if (availableHosters.length === 0) return;
		setResolving(true);
		setPlayError(null);
		try {
			const src = await resolveBestPlay({ data: {
				hosters: availableHosters,
				preferred,
				fresh,
				provider
			} });
			setSource(src);
			setActiveHoster(src.hoster);
			setHosterName(src.hoster);
		} catch (e) {
			setSource(void 0);
			setPlayError(e instanceof Error ? e.message.replace(/^[A-Z]+:/, "") : "Stream nicht ladbar");
		} finally {
			setResolving(false);
		}
	}
	(0, import_react.useEffect)(() => {
		if (availableHosters.length === 0) return;
		loadStream(hosterName || hosterPref);
	}, [
		path,
		lang,
		availableKey
	]);
	(0, import_react.useEffect)(() => {
		if (nextIn === null) return;
		if (nextIn <= 0) {
			setNextIn(null);
			onNext?.();
			return;
		}
		const t = window.setTimeout(() => setNextIn((n) => n === null ? null : n - 1), 1e3);
		return () => window.clearTimeout(t);
	}, [nextIn, onNext]);
	const title = watchQuery.data?.germanTitle || germanTitle;
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
		id: "player",
		className: "relative mb-8 overflow-hidden rounded-xl bg-surface shadow-[var(--shadow-border)]",
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)(VideoSurface, {
				source,
				loading: resolving || watchQuery.isLoading,
				error: playError || watchQuery.error,
				onRetry: () => void loadStream(hosterName || hosterPref, true),
				ctx,
				lang,
				onEnded: hasNext && autoplayNext ? () => setNextIn(5) : void 0,
				onStreamDead: () => void loadStream(hosterName || hosterPref, true)
			}),
			nextIn !== null ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "absolute inset-x-0 bottom-24 z-20 mx-auto flex max-w-sm flex-col items-center gap-3 rounded-lg bg-bg/90 p-4 text-center",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
					className: "text-sm",
					children: [
						"Nächste Folge in ",
						nextIn,
						"s"
					]
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
					className: "flex gap-2",
					children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
						variant: "primary",
						onClick: () => {
							setNextIn(null);
							onNext?.();
						},
						children: "Jetzt"
					}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
						variant: "ghost",
						onClick: () => setNextIn(null),
						children: "Abbrechen"
					})]
				})]
			}) : null,
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "space-y-4 px-4 py-4",
				children: [
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
						className: "flex items-start justify-between gap-3",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
							className: "min-w-0",
							children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h2", {
								className: "font-display text-xl tracking-tight",
								children: title
							}), englishTitle ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
								className: "mt-1 text-sm text-muted",
								children: englishTitle
							}) : null]
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
							className: "flex shrink-0 gap-1",
							children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
								type: "button",
								"aria-label": "Vorherige Folge",
								disabled: !hasPrev,
								onClick: onPrev,
								className: "grid size-11 place-items-center rounded-md text-muted hover:text-fg disabled:opacity-30",
								children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(ChevronLeft, { className: "size-5" })
							}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
								type: "button",
								"aria-label": "Nächste Folge",
								disabled: !hasNext,
								onClick: onNext,
								className: "grid size-11 place-items-center rounded-md text-muted hover:text-fg disabled:opacity-30",
								children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(ChevronRight, { className: "size-5" })
							})]
						})]
					}),
					langPref === "DE" && langs.length > 0 && !langs.includes("DE") ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
						className: "text-xs text-muted",
						children: [
							"Kein GerDub für diese Folge — ",
							langDisplay(lang),
							" wird gespielt."
						]
					}) : null,
					langs.length > 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
						className: "flex flex-wrap gap-2",
						children: langs.map((l) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
							type: "button",
							onClick: () => setLang(l),
							className: cn("h-10 rounded-full px-4 text-sm font-medium transition-colors duration-150", lang === l ? "bg-accent text-accent-fg" : "text-muted shadow-[var(--shadow-border)] hover:text-fg"),
							children: langDisplay(l)
						}, l))
					}) : null,
					availableHosters.length > 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
						className: "flex flex-wrap gap-2",
						children: availableHosters.map((h) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
							type: "button",
							onClick: () => {
								setHosterName(h.name);
								loadStream(h.name, true);
							},
							className: cn("h-10 rounded-md px-3 text-sm transition-colors duration-150", (activeHoster || hosterName) === h.name ? "bg-elevated text-fg" : "text-muted hover:text-fg"),
							children: h.name
						}, h.redirectPath))
					}) : null
				]
			})
		]
	});
}
function VideoSurface({ source, loading, error, onRetry, ctx, lang, onEnded, onStreamDead }) {
	const message = typeof error === "string" ? error : error instanceof Error ? error.message.replace(/^[A-Z]+:/, "") : "Stream gerade nicht ladbar. Anderen Hoster wählen oder nochmal versuchen.";
	if (error && !source) return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
		className: "flex aspect-video flex-col items-center justify-center gap-3 bg-elevated px-6 text-center",
		children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
			className: "max-w-md text-sm text-muted",
			children: message
		}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(Button, {
			variant: "primary",
			onClick: onRetry,
			children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(RotateCw, { className: "size-4" }), "Erneut versuchen"]
		})]
	});
	if (!source) return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
		className: "flex aspect-video items-center justify-center bg-elevated text-muted",
		children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(LoaderCircle, { className: "size-7 animate-spin" })
	});
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
		className: "relative",
		children: [loading ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
			className: "pointer-events-none absolute right-3 top-3 z-30 rounded-full bg-bg/80 p-2",
			children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(LoaderCircle, { className: "size-4 animate-spin text-muted" })
		}) : null, /* @__PURE__ */ (0, import_jsx_runtime.jsx)(MediaPlayer, {
			source,
			ctx,
			lang,
			onEnded,
			onStreamDead
		})]
	});
}
function buildPayload(ctx, positionSec, durationSec, lang) {
	return {
		slug: ctx.slug,
		title: ctx.title,
		season: ctx.season,
		episode: ctx.episode,
		episodePath: ctx.path,
		germanTitle: ctx.germanTitle,
		englishTitle: ctx.englishTitle,
		positionSec,
		durationSec,
		updatedAt: Date.now(),
		lang,
		provider: providerFromPath(ctx.path)
	};
}
function MediaPlayer({ source, ctx, lang, onEnded, onStreamDead }) {
	const videoRef = (0, import_react.useRef)(null);
	const wrapRef = (0, import_react.useRef)(null);
	const hlsRef = (0, import_react.useRef)(null);
	const lastSave = (0, import_react.useRef)(0);
	const lastUi = (0, import_react.useRef)(0);
	const userSeek = (0, import_react.useRef)(false);
	const landed = (0, import_react.useRef)(false);
	const giveUp = (0, import_react.useRef)(false);
	const resumeRef = (0, import_react.useRef)(0);
	const targetRef = (0, import_react.useRef)(0);
	const posRef = (0, import_react.useRef)(0);
	const tries = (0, import_react.useRef)(0);
	const seekLoop = (0, import_react.useRef)(0);
	const speedOpenRef = (0, import_react.useRef)(false);
	const [useDirect, setUseDirect] = (0, import_react.useState)(false);
	const [playing, setPlaying] = (0, import_react.useState)(false);
	const [time, setTime] = (0, import_react.useState)(0);
	const [duration, setDuration] = (0, import_react.useState)(0);
	const [buffered, setBuffered] = (0, import_react.useState)(0);
	const [fs, setFs] = (0, import_react.useState)(false);
	const [cssFs, setCssFs] = (0, import_react.useState)(false);
	const [show, setShow] = (0, import_react.useState)(true);
	const [speedOpen, setSpeedOpen] = (0, import_react.useState)(false);
	const [resumeHint, setResumeHint] = (0, import_react.useState)(0);
	const hideTimer = (0, import_react.useRef)(0);
	const src = !useDirect && source.proxied ? source.proxied : source.url;
	const speed = usePlayback((s) => s.speed);
	const volume = usePlayback((s) => s.volume);
	const muted = usePlayback((s) => s.muted);
	const setSpeed = usePlayback((s) => s.setSpeed);
	const setVolume = usePlayback((s) => s.setVolume);
	const setMuted = usePlayback((s) => s.setMuted);
	speedOpenRef.current = speedOpen;
	function storedPosition() {
		if (!usePlayback.getState().resume) return 0;
		const item = progressForPath(useLibrary.getState().progress, ctx.path, lang);
		return resumePosition(item);
	}
	function applyRate(video) {
		video.playbackRate = usePlayback.getState().speed;
		video.volume = usePlayback.getState().volume;
		video.muted = usePlayback.getState().muted;
	}
	function trySeek(video) {
		if (userSeek.current) return;
		const at = targetRef.current;
		if (at < 8) {
			landed.current = true;
			return;
		}
		const dur = video.duration;
		const ready = Number.isFinite(dur) && dur >= 8;
		if (!ready && !(dur === Infinity)) return;
		const target = ready ? Math.min(at, Math.max(0, dur - 1.5)) : at;
		const cur = video.currentTime || 0;
		if (Math.abs(cur - target) <= 1.25) {
			landed.current = true;
			posRef.current = cur;
			return;
		}
		if (landed.current && cur < 5 && target > 12) landed.current = false;
		if (landed.current) return;
		tries.current += 1;
		if (tries.current > 90) {
			giveUp.current = true;
			return;
		}
		try {
			video.currentTime = target;
		} catch {}
	}
	(0, import_react.useEffect)(() => {
		userSeek.current = false;
		landed.current = false;
		giveUp.current = false;
		tries.current = 0;
		const stored = storedPosition();
		targetRef.current = stored;
		resumeRef.current = stored;
		posRef.current = stored;
		setTime(stored);
		setResumeHint(stored);
		setUseDirect(false);
	}, [ctx.path, lang]);
	(0, import_react.useEffect)(() => {
		const video = videoRef.current;
		if (!video) return;
		hlsRef.current?.destroy();
		hlsRef.current = null;
		userSeek.current = false;
		landed.current = false;
		giveUp.current = false;
		tries.current = 0;
		window.cancelAnimationFrame(seekLoop.current);
		const startAt = storedPosition();
		targetRef.current = startAt;
		resumeRef.current = startAt;
		if (startAt >= 8) setResumeHint(startAt);
		const runSeek = () => trySeek(video);
		const onPlaying = () => {
			applyRate(video);
			runSeek();
		};
		video.addEventListener("loadedmetadata", runSeek);
		video.addEventListener("loadeddata", runSeek);
		video.addEventListener("canplay", runSeek);
		video.addEventListener("playing", onPlaying);
		video.addEventListener("seeked", runSeek);
		const until = performance.now() + 14e3;
		const loop = () => {
			if (!userSeek.current && !landed.current && !giveUp.current && performance.now() < until) {
				runSeek();
				seekLoop.current = requestAnimationFrame(loop);
			}
		};
		seekLoop.current = requestAnimationFrame(loop);
		if (source.kind === "mp4") {
			video.src = src;
			video.play().catch(() => void 0);
		} else if (Hls.isSupported()) {
			const resumeAt = startAt > 8 ? startAt : -1;
			const hls = new Hls({
				enableWorker: true,
				lowLatencyMode: false,
				backBufferLength: 90,
				maxBufferLength: 30,
				startPosition: resumeAt,
				autoStartLoad: resumeAt < 0,
				fragLoadingMaxRetry: 5,
				manifestLoadingMaxRetry: 4,
				startFragPrefetch: true
			});
			hlsRef.current = hls;
			hls.loadSource(src);
			hls.attachMedia(video);
			hls.on(Hls.Events.MANIFEST_PARSED, () => {
				if (resumeAt > 0) hls.startLoad(resumeAt);
				runSeek();
				applyRate(video);
				video.play().catch(() => void 0);
			});
			hls.on(Hls.Events.FRAG_CHANGED, () => runSeek());
			hls.on(Hls.Events.LEVEL_LOADED, () => runSeek());
			hls.on(Hls.Events.FRAG_BUFFERED, () => runSeek());
			hls.on(Hls.Events.ERROR, (_, data) => {
				if (!data.fatal) return;
				if (data.type === Hls.ErrorTypes.NETWORK_ERROR) hls.startLoad(targetRef.current > 8 ? targetRef.current : -1);
				else if (data.type === Hls.ErrorTypes.MEDIA_ERROR) hls.recoverMediaError();
				else onStreamDead?.();
			});
		} else if (video.canPlayType("application/vnd.apple.mpegurl")) {
			video.src = src;
			video.play().catch(() => void 0);
		}
		applyRate(video);
		return () => {
			window.cancelAnimationFrame(seekLoop.current);
			const cur = video.currentTime || 0;
			const dur = video.duration || 0;
			if (shouldPersistProgress({
				current: cur,
				resumeTarget: targetRef.current,
				landed: landed.current,
				userSeek: userSeek.current
			})) recordProgress(buildPayload(ctx, cur, Number.isFinite(dur) ? dur : 0, lang), false);
			video.removeEventListener("loadedmetadata", runSeek);
			video.removeEventListener("loadeddata", runSeek);
			video.removeEventListener("canplay", runSeek);
			video.removeEventListener("playing", onPlaying);
			video.removeEventListener("seeked", runSeek);
			hlsRef.current?.destroy();
			hlsRef.current = null;
			video.removeAttribute("src");
			video.load();
		};
	}, [
		src,
		source.kind,
		ctx.path,
		lang
	]);
	(0, import_react.useEffect)(() => {
		const video = videoRef.current;
		if (!video) return;
		video.playbackRate = speed;
		video.volume = volume;
		video.muted = muted;
	}, [
		speed,
		volume,
		muted,
		src
	]);
	function save(force = false) {
		const video = videoRef.current;
		if (!video) return;
		const position = video.currentTime || 0;
		const dur = video.duration || 0;
		posRef.current = position;
		if (!shouldPersistProgress({
			current: position,
			resumeTarget: targetRef.current,
			landed: landed.current,
			userSeek: userSeek.current
		})) {
			if (giveUp.current && position > 12 && targetRef.current >= 8 && !userSeek.current) {
				userSeek.current = true;
				setResumeHint(0);
			}
			return;
		}
		if (position > 2 && (userSeek.current || landed.current || targetRef.current < 8)) resumeRef.current = position;
		const now = Date.now();
		if (!force && now - lastSave.current < 4e3) return;
		lastSave.current = now;
		recordProgress(buildPayload(ctx, position, Number.isFinite(dur) ? dur : 0, lang), false);
	}
	(0, import_react.useEffect)(() => {
		const onHide = () => save(true);
		window.addEventListener("pagehide", onHide);
		document.addEventListener("visibilitychange", onHide);
		return () => {
			window.removeEventListener("pagehide", onHide);
			document.removeEventListener("visibilitychange", onHide);
			save(true);
		};
	}, [ctx.path, lang]);
	function bumpHide() {
		setShow(true);
		window.clearTimeout(hideTimer.current);
		hideTimer.current = window.setTimeout(() => {
			if (speedOpenRef.current) return;
			if (videoRef.current && !videoRef.current.paused) setShow(false);
		}, 3600);
	}
	(0, import_react.useEffect)(() => {
		const onFs = () => {
			const anyDoc = document;
			setFs(Boolean(document.fullscreenElement || anyDoc.webkitFullscreenElement || cssFs));
		};
		document.addEventListener("fullscreenchange", onFs);
		document.addEventListener("webkitfullscreenchange", onFs);
		return () => {
			document.removeEventListener("fullscreenchange", onFs);
			document.removeEventListener("webkitfullscreenchange", onFs);
		};
	}, [cssFs]);
	(0, import_react.useEffect)(() => {
		function onKey(e) {
			const tag = e.target?.tagName;
			if (tag === "INPUT" || tag === "TEXTAREA") return;
			if (!videoRef.current) return;
			if (e.key === "Escape" && cssFs) {
				setCssFs(false);
				return;
			}
			if (e.key === " " || e.key === "k") {
				e.preventDefault();
				togglePlay();
			} else if (e.key === "ArrowRight" || e.key === "l") skip(10);
			else if (e.key === "ArrowLeft" || e.key === "j") skip(-10);
			else if (e.key === "f") {
				e.preventDefault();
				toggleFs();
			} else if (e.key === "m") setMuted(!usePlayback.getState().muted);
			else if (e.key === "ArrowUp") {
				e.preventDefault();
				setVolume(Math.min(1, usePlayback.getState().volume + .05));
			} else if (e.key === "ArrowDown") {
				e.preventDefault();
				setVolume(Math.max(0, usePlayback.getState().volume - .05));
			}
		}
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	}, [
		setMuted,
		setVolume,
		cssFs
	]);
	function togglePlay() {
		const video = videoRef.current;
		if (!video) return;
		if (video.paused) video.play();
		else video.pause();
		bumpHide();
	}
	async function toggleFs() {
		const wrap = wrapRef.current;
		const video = videoRef.current;
		if (!wrap || !video) return;
		const anyDoc = document;
		const anyWrap = wrap;
		bumpHide();
		if (cssFs) {
			setCssFs(false);
			setFs(false);
			return;
		}
		if (document.fullscreenElement || anyDoc.webkitFullscreenElement) {
			if (document.exitFullscreen) document.exitFullscreen();
			else anyDoc.webkitExitFullscreen?.();
			return;
		}
		if (/iPhone|iPad|iPod/i.test(navigator.userAgent) && typeof video.webkitEnterFullscreen === "function") try {
			video.webkitEnterFullscreen();
			setFs(true);
			return;
		} catch {}
		const req = wrap.requestFullscreen || anyWrap.webkitRequestFullscreen;
		if (req) try {
			await Promise.resolve(req.call(wrap));
			setFs(true);
			return;
		} catch {}
		setCssFs(true);
		setFs(true);
	}
	async function pip() {
		const video = videoRef.current;
		if (!video) return;
		try {
			if (document.pictureInPictureElement) await document.exitPictureInPicture();
			else await video.requestPictureInPicture();
		} catch {}
	}
	function skip(delta) {
		const video = videoRef.current;
		if (!video) return;
		userSeek.current = true;
		landed.current = true;
		const dur = Number.isFinite(video.duration) ? video.duration : 0;
		const next = Math.max(0, Math.min(dur || Infinity, (video.currentTime || 0) + delta));
		video.currentTime = next;
		posRef.current = next;
		setTime(next);
		save(true);
		bumpHide();
	}
	function seekTo(ratio) {
		const video = videoRef.current;
		if (!video || !Number.isFinite(video.duration) || video.duration <= 0) return;
		userSeek.current = true;
		landed.current = true;
		video.currentTime = Math.max(0, Math.min(video.duration, ratio * video.duration));
		save(true);
	}
	function onBar(e) {
		e.stopPropagation();
		const rect = e.currentTarget.getBoundingClientRect();
		seekTo(Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width)));
	}
	function restart() {
		const video = videoRef.current;
		userSeek.current = true;
		landed.current = true;
		giveUp.current = true;
		resumeRef.current = 0;
		targetRef.current = 0;
		setResumeHint(0);
		if (video) {
			video.currentTime = 0;
			video.play().catch(() => void 0);
		}
		bumpHide();
	}
	const pct = duration > 0 ? time / duration * 100 : 0;
	const bufPct = duration > 0 ? buffered / duration * 100 : 0;
	const nativeFs = fs && !cssFs;
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
		ref: wrapRef,
		className: cn("relative bg-elevated", cssFs ? "nori-player-fs" : "aspect-video"),
		"data-nori-fs": cssFs || fs ? "1" : "0",
		onPointerMove: bumpHide,
		onPointerDown: bumpHide,
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("video", {
				ref: videoRef,
				className: "h-full w-full",
				playsInline: true,
				preload: "auto",
				onClick: (e) => {
					e.stopPropagation();
					if (!show) {
						bumpHide();
						return;
					}
					togglePlay();
				},
				onPlay: () => {
					setPlaying(true);
					const video = videoRef.current;
					if (video) video.playbackRate = usePlayback.getState().speed;
				},
				onPause: () => {
					setPlaying(false);
					setShow(true);
					save(true);
				},
				onTimeUpdate: () => {
					const video = videoRef.current;
					if (!video) return;
					const now = performance.now();
					if (now - lastUi.current > 200) {
						lastUi.current = now;
						setTime(video.currentTime || 0);
						setDuration(Number.isFinite(video.duration) ? video.duration : 0);
						if (video.buffered.length > 0) try {
							setBuffered(video.buffered.end(video.buffered.length - 1));
						} catch {}
					}
					save(false);
				},
				onLoadedMetadata: () => {
					const video = videoRef.current;
					if (!video) return;
					setDuration(Number.isFinite(video.duration) ? video.duration : 0);
					video.playbackRate = usePlayback.getState().speed;
				},
				onEnded: () => {
					const dur = videoRef.current?.duration || posRef.current || 0;
					recordProgress({
						...buildPayload(ctx, dur, dur, lang),
						completed: true
					}, false);
					onEnded?.();
				},
				onError: () => {
					if (!useDirect) setUseDirect(true);
				}
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: cn("pointer-events-none absolute inset-0 bg-gradient-to-t from-bg via-transparent to-transparent transition-opacity duration-200", show ? "opacity-100" : "opacity-0") }),
			resumeHint >= 8 && time < resumeHint - 3 && !userSeek.current ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "absolute top-3 left-3 z-30 flex items-center gap-2 rounded-md bg-bg/85 px-3 py-2 text-xs",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("button", {
					type: "button",
					className: "underline-offset-2 hover:underline",
					onClick: () => {
						const video = videoRef.current;
						if (!video) return;
						userSeek.current = false;
						landed.current = false;
						giveUp.current = false;
						tries.current = 0;
						try {
							video.currentTime = targetRef.current;
						} catch {}
						bumpHide();
					},
					children: ["Weiter bei ", formatClock(resumeHint)]
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
					type: "button",
					className: "text-muted underline-offset-2 hover:underline",
					onClick: restart,
					children: "Von vorn"
				})]
			}) : null,
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: cn("absolute inset-x-0 bottom-0 z-30 space-y-2 px-3 pb-3 transition-opacity duration-200", show ? "pointer-events-auto opacity-100" : "pointer-events-none opacity-0"),
				onPointerDown: (e) => e.stopPropagation(),
				onClick: (e) => e.stopPropagation(),
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
					className: "relative h-11 cursor-pointer",
					onPointerDown: onBar,
					role: "slider",
					"aria-valuemin": 0,
					"aria-valuemax": Math.round(duration),
					"aria-valuenow": Math.round(time),
					tabIndex: 0,
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("span", {
						className: "absolute inset-x-0 top-1/2 h-1.5 -translate-y-1/2 rounded-full bg-fg/20",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
							className: "absolute inset-y-0 left-0 rounded-full bg-fg/30",
							style: { width: `${bufPct}%` }
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
							className: "absolute inset-y-0 left-0 rounded-full bg-accent",
							style: { width: `${pct}%` }
						})]
					})
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
					className: "flex items-center gap-0.5 text-fg",
					children: [
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)(IconBtn, {
							label: playing ? "Pause" : "Play",
							onClick: togglePlay,
							children: playing ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Pause, { className: "size-5" }) : /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Play, { className: "size-5" })
						}),
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)(IconBtn, {
							label: "10 Sekunden zurück",
							onClick: () => skip(-10),
							children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(SkipBack, { className: "size-5" })
						}),
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)(IconBtn, {
							label: "10 Sekunden vor",
							onClick: () => skip(10),
							children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(SkipForward, { className: "size-5" })
						}),
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)(IconBtn, {
							label: muted ? "Ton an" : "Stumm",
							onClick: () => setMuted(!muted),
							children: muted || volume === 0 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)(VolumeX, { className: "size-5" }) : /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Volume2, { className: "size-5" })
						}),
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							type: "range",
							min: 0,
							max: 1,
							step: .05,
							value: muted ? 0 : volume,
							onChange: (e) => {
								const v = Number(e.target.value);
								setVolume(v);
								setMuted(v === 0);
								const video = videoRef.current;
								if (video) {
									video.volume = v;
									video.muted = v === 0;
								}
							},
							onPointerDown: (e) => e.stopPropagation(),
							className: "hidden h-11 w-20 accent-accent sm:block",
							"aria-label": "Lautstärke"
						}),
						/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("span", {
							className: "ml-1 min-w-16 font-mono text-xs tabular-nums text-muted",
							"data-nori-time": String(Math.floor(time)),
							"data-nori-duration": String(Math.floor(duration)),
							children: [
								formatClock(time),
								" / ",
								formatClock(duration)
							]
						}),
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { className: "flex-1" }),
						/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
							className: "relative",
							children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(IconBtn, {
								label: "Geschwindigkeit",
								wide: true,
								onClick: () => {
									setSpeedOpen((v) => !v);
									bumpHide();
								},
								children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("span", {
									className: "flex items-center gap-1",
									children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Gauge, { className: "size-5" }), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
										className: "text-xs tabular-nums",
										children: speed === 1 ? "1×" : `${speed}×`
									})]
								})
							}), speedOpen ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
								className: "absolute right-0 bottom-12 z-40 min-w-24 rounded-md bg-surface p-1 shadow-[var(--shadow-border)]",
								children: [
									.75,
									1,
									1.25,
									1.5,
									2
								].map((s) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
									type: "button",
									onPointerDown: (e) => e.stopPropagation(),
									onClick: (e) => {
										e.stopPropagation();
										setSpeed(s);
										const video = videoRef.current;
										if (video) video.playbackRate = s;
										setSpeedOpen(false);
									},
									className: cn("flex h-11 w-full items-center rounded-sm px-3 text-sm", speed === s ? "text-fg" : "text-muted hover:text-fg"),
									children: s === 1 ? "Normal" : `${s}×`
								}, s))
							}) : null]
						}),
						typeof document !== "undefined" && "pictureInPictureEnabled" in document ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
							className: "hidden sm:contents",
							children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(IconBtn, {
								label: "Bild-im-Bild",
								onClick: () => void pip(),
								children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(PictureInPicture2, { className: "size-5" })
							})
						}) : null,
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)(IconBtn, {
							label: nativeFs || cssFs ? "Vollbild beenden" : "Vollbild",
							onClick: () => void toggleFs(),
							children: nativeFs || cssFs ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Minimize, { className: "size-5" }) : /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Maximize, { className: "size-5" })
						})
					]
				})]
			})
		]
	});
}
function IconBtn({ label, onClick, children, wide }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
		type: "button",
		"aria-label": label,
		onPointerDown: (e) => e.stopPropagation(),
		onClick: (e) => {
			e.stopPropagation();
			onClick();
		},
		className: cn("grid h-11 place-items-center rounded-md text-fg hover:bg-fg/10", wide ? "min-w-11 px-2" : "w-11"),
		children
	});
}
function unique(list) {
	const out = [];
	for (const item of list) if (!out.includes(item)) out.push(item);
	return out;
}
function WatchPage() {
	const { slug } = Route$6.useParams();
	const { season, ep } = Route$6.useSearch();
	const navigate = useNavigate({ from: "/watch/$slug" });
	const titles = useLibrary((s) => s.titles);
	const progressMap = useLibrary((s) => s.progress);
	const latest = progressForSlug(progressMap, slug);
	const currentProvider = useProvider((s) => s.provider);
	const setProvider = useProvider((s) => s.setProvider);
	const hinted = hintProviderForSlug(slug, currentProvider, latest?.episodePath);
	const coverArt = useCover(slug);
	const seriesQuery = useQuery({
		queryKey: [
			"series-smart",
			hinted,
			slug,
			season ?? ""
		],
		queryFn: () => fetchSeriesSmart({
			slug,
			season,
			provider: hinted
		}),
		staleTime: 6e5,
		retry: 1
	});
	const series = seriesQuery.data?.series;
	const provider = seriesQuery.data?.provider ?? hinted;
	const title = series?.title || titles[slug] || slug;
	const episodes = series?.episodes ?? [];
	const activeSeason = season || series?.activeSeason || "1";
	(0, import_react.useEffect)(() => {
		if (seriesQuery.data?.provider && seriesQuery.data.provider !== currentProvider) setProvider(seriesQuery.data.provider);
	}, [
		seriesQuery.data?.provider,
		currentProvider,
		setProvider
	]);
	(0, import_react.useEffect)(() => {
		if (title && title !== slug) requestCover({
			slug,
			title,
			kind: kindFromProvider(provider)
		});
	}, [
		slug,
		title,
		provider
	]);
	const currentIndex = (0, import_react.useMemo)(() => {
		if (ep) {
			const i = episodes.findIndex((e) => String(e.number) === ep);
			if (i >= 0) return i;
		}
		if (latest && (!season || latest.season === activeSeason)) {
			const i = episodes.findIndex((e) => e.number === latest.episode);
			if (i >= 0) return i;
		}
		return episodes.length ? 0 : -1;
	}, [
		episodes,
		ep,
		latest,
		season,
		activeSeason
	]);
	const current = currentIndex >= 0 ? episodes[currentIndex] : void 0;
	const numericSeasons = (series?.seasons ?? []).filter((s) => s.id !== "filme");
	const seasonPos = numericSeasons.findIndex((s) => s.id === activeSeason);
	const nextSeasonId = activeSeason !== "filme" && seasonPos >= 0 ? numericSeasons[seasonPos + 1]?.id : void 0;
	const hasPrev = currentIndex > 0;
	const hasNext = Boolean(current) && (currentIndex < episodes.length - 1 || Boolean(nextSeasonId));
	(0, import_react.useEffect)(() => {
		if (!current || ep) return;
		navigate({
			search: {
				season: activeSeason,
				ep: String(current.number)
			},
			replace: true
		});
	}, [
		current,
		ep,
		activeSeason,
		navigate
	]);
	function go(nextEp, nextSeason) {
		navigate({
			search: {
				season: nextSeason || activeSeason,
				ep: nextEp ? String(nextEp) : void 0
			},
			replace: true
		});
	}
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(CoverToneRoot, {
		src: coverArt?.banner || coverArt?.poster,
		children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("main", {
			className: "mx-auto max-w-6xl px-4 pb-24 pt-4",
			children: [
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
					className: "mb-4 flex items-center gap-3",
					children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(Link, {
						to: "/anime/$slug",
						params: { slug },
						search: { season: activeSeason },
						className: "inline-flex h-11 items-center gap-2 text-sm text-muted hover:text-fg",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(ArrowLeft, { className: "size-4" }), title]
					})
				}),
				current?.path ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)(WatchPlayer, {
					ctx: {
						slug,
						title,
						season: activeSeason,
						episode: current.number,
						path: current.path,
						germanTitle: current.germanTitle,
						englishTitle: current.englishTitle
					},
					hasPrev,
					hasNext,
					onPrev: () => currentIndex > 0 && go(episodes[currentIndex - 1].number),
					onNext: () => {
						if (currentIndex < episodes.length - 1) go(episodes[currentIndex + 1].number);
						else if (nextSeasonId) go(1, nextSeasonId);
					}
				}) : seriesQuery.isLoading ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "aspect-video animate-pulse rounded-xl bg-surface" }) : /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "rounded-xl bg-surface p-6 text-sm text-muted",
					children: "Folge gerade nicht ladbar."
				}),
				series && series.seasons.length > 1 ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
					className: "mt-6 mb-4 flex gap-2 overflow-x-auto pb-1 scrollbar-none",
					children: series.seasons.map((s) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
						type: "button",
						onClick: () => go(1, s.id),
						className: cn("h-10 shrink-0 rounded-full px-4 text-sm", activeSeason === s.id ? "bg-accent text-accent-fg" : "text-muted shadow-[var(--shadow-border)]"),
						children: s.label
					}, s.id))
				}) : null,
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("ol", {
					className: "mt-4 divide-y divide-fg/10 overflow-hidden rounded-lg bg-surface",
					children: episodes.map((episode, i) => {
						const prog = progressForEpisode(progressMap, {
							path: episode.path,
							slug,
							season: activeSeason,
							episode: episode.number
						});
						const complete = isEpisodeComplete(prog);
						const ratio = watchRatio(prog);
						return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("li", { children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("button", {
							type: "button",
							onClick: () => go(episode.number),
							className: cn("flex w-full items-center gap-3 px-4 py-3 text-left text-sm hover:bg-elevated", i === currentIndex && "bg-elevated"),
							children: [
								/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
									className: "relative w-8 text-muted",
									children: complete ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Check, { className: "size-4 text-fg" }) : String(episode.number).padStart(2, "0")
								}),
								/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
									className: "min-w-0 flex-1 truncate",
									children: episode.germanTitle
								}),
								ratio > 0 && !complete ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("span", {
									className: "flex w-16 shrink-0 flex-col items-end gap-1",
									children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("span", {
										className: "text-xs tabular-nums text-subtle",
										children: [Math.round(ratio * 100), "%"]
									}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
										className: "block h-1 w-full rounded-full bg-fg/15",
										children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
											className: "block h-full rounded-full bg-accent",
											style: { width: `${Math.round(ratio * 100)}%` }
										})
									})]
								}) : complete ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
									className: "text-xs text-subtle",
									children: "Gesehen"
								}) : null
							]
						}) }, episode.path || episode.number);
					})
				})
			]
		})
	});
}
//#endregion
export { WatchPage as component };
