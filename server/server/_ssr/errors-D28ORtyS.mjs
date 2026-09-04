//#region node_modules/.nitro/vite/services/ssr/assets/errors-D28ORtyS.js
function scrapeFail(code, message) {
	return /* @__PURE__ */ new Error(`${code.toUpperCase()}:${message}`);
}
function parseScrapeError(err) {
	const raw = err instanceof Error ? err.message : String(err || "Fehler");
	const m = raw.match(/^(NOTFOUND|BLOCKED|PARSE|HOSTER):([\s\S]+)$/);
	if (m) return {
		code: m[1].toLowerCase(),
		message: m[2].trim()
	};
	if (/nicht erreichbar|timeout|403|429|blocked/i.test(raw)) return {
		code: "blocked",
		message: raw
	};
	return {
		code: "unknown",
		message: raw
	};
}
//#endregion
export { scrapeFail as n, parseScrapeError as t };
