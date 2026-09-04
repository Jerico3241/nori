import { n as create, t as persist } from "../_libs/zustand.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/playback-CYrpmXej.js
var LANG_PREFS = [
	"DE",
	"GerSub",
	"EN"
];
var HOST_PREFS = [
	"VOE",
	"Vidmoly",
	"Filemoon",
	"Doodstream"
];
function langDisplay(lang) {
	if (lang === "DE") return "GerDub";
	return lang;
}
function pickLang(langs, pref) {
	if (langs.length === 0) return pref;
	if (langs.includes(pref)) return pref;
	return [
		"DE",
		"GerSub",
		"EN"
	].find((l) => langs.includes(l)) ?? langs[0];
}
function pickHoster(names, pref) {
	if (names.length === 0) return pref;
	const want = pref.toLowerCase();
	const hit = names.find((n) => n.toLowerCase() === want);
	if (hit) return hit;
	return names.find((n) => n.toLowerCase() === "voe") ?? names[0];
}
var usePlayback = create()(persist((set) => ({
	langPref: "DE",
	hosterPref: "VOE",
	autoplayNext: true,
	resume: true,
	speed: 1,
	volume: 1,
	muted: false,
	setLangPref: (langPref) => set({ langPref }),
	setHosterPref: (hosterPref) => set({ hosterPref }),
	setAutoplayNext: (autoplayNext) => set({ autoplayNext }),
	setResume: (resume) => set({ resume }),
	setSpeed: (speed) => set({ speed }),
	setVolume: (volume) => set({ volume }),
	setMuted: (muted) => set({ muted })
}), {
	name: "nori-playback",
	version: 1
}));
//#endregion
export { pickLang as a, pickHoster as i, LANG_PREFS as n, usePlayback as o, langDisplay as r, HOST_PREFS as t };
