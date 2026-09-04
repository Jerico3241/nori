import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { a as Toggle, i as SettingsScreen, t as Chip } from "./settings-ui-DICpPGye.mjs";
import { n as LANG_PREFS, o as usePlayback, r as langDisplay, t as HOST_PREFS } from "./playback-CYrpmXej.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/einstellungen.wiedergabe-B0VgPhWk.js
var import_jsx_runtime = require_jsx_runtime();
function WiedergabePage() {
	const langPref = usePlayback((s) => s.langPref);
	const hosterPref = usePlayback((s) => s.hosterPref);
	const autoplayNext = usePlayback((s) => s.autoplayNext);
	const resume = usePlayback((s) => s.resume);
	const speed = usePlayback((s) => s.speed);
	const setLangPref = usePlayback((s) => s.setLangPref);
	const setHosterPref = usePlayback((s) => s.setHosterPref);
	const setAutoplayNext = usePlayback((s) => s.setAutoplayNext);
	const setResume = usePlayback((s) => s.setResume);
	const setSpeed = usePlayback((s) => s.setSpeed);
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(SettingsScreen, {
		kicker: "Wiedergabe",
		title: "Sprache & Player",
		hint: "Diese Werte gelten für jede Folge, bis du sie änderst.",
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
				className: "mt-8 rounded-xl bg-surface p-5 shadow-[var(--shadow-border)]",
				children: [
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h2", {
						className: "font-display text-lg tracking-tight",
						children: "Sprache"
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "mt-1 text-sm text-muted",
						children: "GerDub ist die deutsche Synchronisation, GerSub Untertitel."
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
						className: "mt-4 flex flex-wrap gap-2",
						children: LANG_PREFS.map((l) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Chip, {
							active: langPref === l,
							onClick: () => setLangPref(l),
							children: langDisplay(l)
						}, l))
					})
				]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
				className: "mt-4 rounded-xl bg-surface p-5 shadow-[var(--shadow-border)]",
				children: [
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h2", {
						className: "font-display text-lg tracking-tight",
						children: "Hoster"
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "mt-1 text-sm text-muted",
						children: "Falls der Hoster fehlt, nimmt Nori den nächsten."
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
						className: "mt-4 flex flex-wrap gap-2",
						children: HOST_PREFS.map((h) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Chip, {
							active: hosterPref.toLowerCase() === h.toLowerCase(),
							onClick: () => setHosterPref(h),
							children: h
						}, h))
					})
				]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
				className: "mt-4 overflow-hidden rounded-xl bg-surface shadow-[var(--shadow-border)]",
				children: [
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Toggle, {
						label: "Weiterschauen an der letzten Stelle",
						on: resume,
						onChange: setResume
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "h-px bg-fg/10" }),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Toggle, {
						label: "Nächste Folge automatisch",
						on: autoplayNext,
						onChange: setAutoplayNext
					})
				]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
				className: "mt-4 rounded-xl bg-surface p-5 shadow-[var(--shadow-border)]",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h2", {
					className: "font-display text-lg tracking-tight",
					children: "Tempo"
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
					className: "mt-3 flex flex-wrap gap-2",
					children: [
						.75,
						1,
						1.25,
						1.5,
						2
					].map((s) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Chip, {
						active: speed === s,
						onClick: () => setSpeed(s),
						children: s === 1 ? "Normal" : `${s}×`
					}, s))
				})]
			})
		]
	});
}
//#endregion
export { WiedergabePage as component };
