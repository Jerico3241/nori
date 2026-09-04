import { n as create, t as persist } from "../_libs/zustand.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/provider-B-pxa-h2.js
var PROVIDER_META = {
	aniworld: {
		id: "aniworld",
		label: "Anime",
		kind: "Anime",
		hint: "Anime von aniworld.to",
		origin: "https://aniworld.to"
	},
	serienstream: {
		id: "serienstream",
		label: "Serien",
		kind: "Serien",
		hint: "Serien von serienstream.to",
		origin: "https://serienstream.to"
	}
};
Object.values(PROVIDER_META);
function isCatalogProvider(value) {
	return value === "aniworld" || value === "serienstream";
}
function asProvider(value) {
	return value === "serienstream" ? "serienstream" : "aniworld";
}
function otherProvider(value) {
	return asProvider(value) === "serienstream" ? "aniworld" : "serienstream";
}
function providerFromPath(path) {
	if (path && /\/serie\//.test(path)) return "serienstream";
	return "aniworld";
}
function kindFromProvider(provider) {
	return provider === "serienstream" ? "series" : "anime";
}
var useProvider = create()(persist((set) => ({
	provider: "aniworld",
	setProvider: (provider) => set({ provider })
}), {
	name: "nori-provider",
	version: 1,
	skipHydration: true
}));
//#endregion
export { otherProvider as a, kindFromProvider as i, asProvider as n, providerFromPath as o, isCatalogProvider as r, useProvider as s, PROVIDER_META as t };
