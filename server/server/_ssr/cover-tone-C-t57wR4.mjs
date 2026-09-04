import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { t as cn } from "./cn-Ccejyh36.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/cover-tone-C-t57wR4.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
var DEFAULT_TONE = {
	accent: "215 222 234",
	accentFg: "5 6 10",
	muted: "168 178 198",
	dim: "18 22 34",
	glow: "140 160 210",
	wash: "28 36 58",
	ready: false
};
var memory = /* @__PURE__ */ new Map();
var inflight = /* @__PURE__ */ new Map();
var STORE_KEY = "nori-cover-tone-v2";
function clamp(n, a = 0, b = 255) {
	return Math.max(a, Math.min(b, n));
}
function luma(r, g, b) {
	return .2126 * r + .7152 * g + .0722 * b;
}
function sat(r, g, b) {
	const max = Math.max(r, g, b);
	const min = Math.min(r, g, b);
	if (max === 0) return 0;
	return (max - min) / max;
}
function rgb(r, g, b) {
	return `${Math.round(clamp(r))} ${Math.round(clamp(g))} ${Math.round(clamp(b))}`;
}
function rgbToHsl(r, g, b) {
	r /= 255;
	g /= 255;
	b /= 255;
	const max = Math.max(r, g, b);
	const min = Math.min(r, g, b);
	const l = (max + min) / 2;
	if (max === min) return [
		0,
		0,
		l
	];
	const d = max - min;
	const s = l > .5 ? d / (2 - max - min) : d / (max + min);
	let h = 0;
	if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
	else if (max === g) h = ((b - r) / d + 2) / 6;
	else h = ((r - g) / d + 4) / 6;
	return [
		h,
		s,
		l
	];
}
function hue2rgb(p, q, t) {
	if (t < 0) t += 1;
	if (t > 1) t -= 1;
	if (t < 1 / 6) return p + (q - p) * 6 * t;
	if (t < 1 / 2) return q;
	if (t < 2 / 3) return p + (q - p) * ((2 / 3 - t) * 6);
	return p;
}
function hslToRgb(h, s, l) {
	if (s <= 0) {
		const v = l * 255;
		return [
			v,
			v,
			v
		];
	}
	const q = l < .5 ? l * (1 + s) : l + s - l * s;
	const p = 2 * l - q;
	return [
		hue2rgb(p, q, h + 1 / 3) * 255,
		hue2rgb(p, q, h) * 255,
		hue2rgb(p, q, h - 1 / 3) * 255
	];
}
function toneToCss(tone) {
	return {
		"--tone-accent": tone.accent,
		"--tone-fg": tone.accentFg,
		"--tone-muted": tone.muted,
		"--tone-dim": tone.dim,
		"--tone-glow": tone.glow,
		"--tone-wash": tone.wash
	};
}
function applyTone(el, tone) {
	const css = toneToCss(tone);
	for (const [key, value] of Object.entries(css)) el.style.setProperty(key, value);
	el.style.setProperty("--color-accent", `rgb(${tone.accent})`);
	el.style.setProperty("--color-accent-fg", `rgb(${tone.accentFg})`);
	el.style.setProperty("--nori-accent", `rgb(${tone.accent})`);
	if (tone.ready) {
		el.style.setProperty("--color-surface", `color-mix(in oklab, rgb(${tone.dim}) 52%, #0b0d12)`);
		el.style.setProperty("--color-elevated", `color-mix(in oklab, rgb(${tone.wash}) 42%, #141822)`);
		el.dataset.tone = "cover";
	} else {
		el.style.removeProperty("--color-surface");
		el.style.removeProperty("--color-elevated");
		delete el.dataset.tone;
	}
}
function readStore(src) {
	if (typeof window === "undefined") return null;
	try {
		const raw = window.sessionStorage.getItem(STORE_KEY);
		if (!raw) return null;
		const hit = JSON.parse(raw)[src];
		if (!hit?.accent) return null;
		return hit;
	} catch {
		return null;
	}
}
function writeStore(src, tone) {
	if (typeof window === "undefined") return;
	try {
		const raw = window.sessionStorage.getItem(STORE_KEY);
		const parsed = raw ? JSON.parse(raw) : {};
		parsed[src] = tone;
		const keys = Object.keys(parsed);
		if (keys.length > 48) for (const key of keys.slice(0, keys.length - 48)) delete parsed[key];
		window.sessionStorage.setItem(STORE_KEY, JSON.stringify(parsed));
	} catch {}
}
function sample(data) {
	let best = {
		score: -1,
		r: 180,
		g: 190,
		b: 210
	};
	let sumR = 0;
	let sumG = 0;
	let sumB = 0;
	let count = 0;
	for (let i = 0; i < data.length; i += 4) {
		if (data[i + 3] < 200) continue;
		const r = data[i];
		const g = data[i + 1];
		const b = data[i + 2];
		const y = luma(r, g, b);
		if (y < 16 || y > 242) continue;
		const s = sat(r, g, b);
		sumR += r;
		sumG += g;
		sumB += b;
		count += 1;
		const mid = 1 - Math.abs(y - 120) / 255;
		const score = s * 1.7 + mid * .45;
		if (score > best.score) best = {
			score,
			r,
			g,
			b
		};
	}
	if (count === 0) return {
		...DEFAULT_TONE,
		ready: true
	};
	const avg = [
		sumR / count,
		sumG / count,
		sumB / count
	];
	let seed = [
		best.r,
		best.g,
		best.b
	];
	if (sat(seed[0], seed[1], seed[2]) < .16) seed = avg;
	const [h, s] = rgbToHsl(seed[0], seed[1], seed[2]);
	const chroma = Math.min(.82, Math.max(s < .1 ? .08 : .52, s * 1.55));
	const accent = hslToRgb(h, chroma, s < .1 ? .72 : .62);
	const wash = hslToRgb(h, Math.min(.62, chroma * .8), .18);
	const dim = hslToRgb(h, Math.min(.55, chroma * .65), .1);
	const glow = hslToRgb(h, chroma, .64);
	const muted = hslToRgb(h, Math.min(.18, chroma * .28), .72);
	const fg = luma(accent[0], accent[1], accent[2]) > 168 ? [
		12,
		14,
		20
	] : [
		248,
		250,
		252
	];
	return {
		accent: rgb(accent[0], accent[1], accent[2]),
		accentFg: rgb(fg[0], fg[1], fg[2]),
		muted: rgb(muted[0], muted[1], muted[2]),
		dim: rgb(dim[0], dim[1], dim[2]),
		glow: rgb(glow[0], glow[1], glow[2]),
		wash: rgb(wash[0], wash[1], wash[2]),
		ready: true
	};
}
function loadImage(src, cors = true) {
	return new Promise((resolve, reject) => {
		const img = new Image();
		if (cors && !src.startsWith("blob:")) img.crossOrigin = "anonymous";
		img.decoding = "async";
		img.onload = () => resolve(img);
		img.onerror = () => reject(/* @__PURE__ */ new Error("tone image"));
		img.src = src;
	});
}
function toneUrl(src) {
	if (src.startsWith("https://image.tmdb.org/")) return `/api/cover?src=${encodeURIComponent(src)}`;
	return src;
}
async function analyze(src) {
	let objectUrl = null;
	try {
		let img;
		try {
			const res = await fetch(toneUrl(src));
			if (!res.ok) throw new Error("tone fetch");
			const blob = await res.blob();
			objectUrl = URL.createObjectURL(blob);
			img = await loadImage(objectUrl, false);
		} catch {
			img = await loadImage(src);
		}
		const canvas = document.createElement("canvas");
		const size = 48;
		canvas.width = size;
		canvas.height = size;
		const ctx = canvas.getContext("2d", { willReadFrequently: true });
		if (!ctx) return DEFAULT_TONE;
		ctx.drawImage(img, 0, 0, size, size);
		return sample(ctx.getImageData(0, 0, size, size).data);
	} catch {
		return DEFAULT_TONE;
	} finally {
		if (objectUrl) URL.revokeObjectURL(objectUrl);
	}
}
async function extractCoverTone(src) {
	if (!src || typeof window === "undefined") return DEFAULT_TONE;
	const cached = memory.get(src);
	if (cached) return cached;
	const stored = readStore(src);
	if (stored) {
		memory.set(src, stored);
		return stored;
	}
	const pending = inflight.get(src);
	if (pending) return pending;
	const job = analyze(src).then((tone) => {
		memory.set(src, tone);
		if (tone.ready) writeStore(src, tone);
		inflight.delete(src);
		return tone;
	});
	inflight.set(src, job);
	return job;
}
function CoverToneRoot({ src, className, children, global = true }) {
	const [tone, setTone] = (0, import_react.useState)(DEFAULT_TONE);
	(0, import_react.useEffect)(() => {
		if (!src) {
			setTone(DEFAULT_TONE);
			return;
		}
		let live = true;
		extractCoverTone(src).then((next) => {
			if (live) setTone(next);
		});
		return () => {
			live = false;
		};
	}, [src]);
	(0, import_react.useEffect)(() => {
		if (!global || typeof document === "undefined") return;
		applyTone(document.documentElement, tone);
		return () => applyTone(document.documentElement, DEFAULT_TONE);
	}, [tone, global]);
	const style = (0, import_react.useMemo)(() => ({
		...toneToCss(tone),
		"--color-accent": `rgb(${tone.accent})`,
		"--color-accent-fg": `rgb(${tone.accentFg})`
	}), [tone]);
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
		className: cn("nori-tone", tone.ready && "is-ready", className),
		"data-tone": tone.ready ? "cover" : "default",
		style,
		children
	});
}
//#endregion
export { CoverToneRoot as t };
