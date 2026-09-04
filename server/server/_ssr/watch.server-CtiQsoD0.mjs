import { n as scrapeFail } from "./errors-D28ORtyS.mjs";
import { r as resolveHosterRedirect } from "./http.server-D7YcQUwF.mjs";
import { SS_HEADERS, fetchSerienstreamPage, parseWatch } from "./scrape.server-CxlWdT5G.mjs";
import { extractFromHoster, rankHosters } from "./watch.server-Djsupa21.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/watch.server-CtiQsoD0.js
var PLAY_TTL = 7e4;
var REDIRECT_TTL = 24e4;
var ORIGIN = "https://serienstream.to";
var watchCache = /* @__PURE__ */ new Map();
var redirectCache = /* @__PURE__ */ new Map();
var playCache = /* @__PURE__ */ new Map();
async function getWatch(path) {
	const clean = path.split("?")[0];
	if (!clean.startsWith("/serie/")) throw scrapeFail("parse", "Ungültiger Pfad");
	const hit = watchCache.get(clean);
	if (hit && hit.expires > Date.now()) return hit.value;
	const html = await fetchSerienstreamPage(clean);
	const info = parseWatch(html, clean);
	if (info.hosters.length === 0) throw scrapeFail("parse", "Keine Hoster gefunden");
	watchCache.set(clean, {
		value: info,
		expires: Date.now() + 6e5
	});
	return info;
}
function looksCaptcha(html) {
	const h = html.slice(0, 4e3).toLowerCase();
	return h.includes("cf-turnstile") || h.includes("g-recaptcha") || h.includes("hcaptcha") || h.includes("just a moment") || h.includes("ddos-guard");
}
function extractHosterUrl(html, finalUrl) {
	const bounce = html.match(/window\.location(?:\.href)?\s*=\s*['"](https?:\/\/[^'"]+)['"]/i)?.[1] || html.match(/location\.replace\(\s*['"](https?:\/\/[^'"]+)['"]/i)?.[1];
	if (bounce && !bounce.includes("serienstream.to") && !bounce.includes("translate.google")) return bounce;
	const iframe = html.match(/<iframe[^>]+src=["'](https?:\/\/[^"']+)["']/i)?.[1];
	if (iframe && !iframe.includes("serienstream") && !iframe.includes("translate.google")) return iframe;
	try {
		const u = new URL(finalUrl);
		if (!u.hostname.includes("serienstream") && !u.hostname.includes("translate.goog")) return `${u.protocol}//${u.hostname}${u.pathname}`;
	} catch {}
	return null;
}
async function followPlayUrl(playUrl) {
	const path = playUrl.startsWith("http") ? playUrl : `${ORIGIN}${playUrl.startsWith("/") ? playUrl : `/${playUrl}`}`;
	const hit = redirectCache.get(path);
	if (hit && hit.expires > Date.now()) return hit.url;
	try {
		const direct = await resolveHosterRedirect(path, `${ORIGIN}/`);
		if (direct) {
			redirectCache.set(path, {
				url: direct,
				expires: Date.now() + REDIRECT_TTL
			});
			return direct;
		}
	} catch {}
	const encoded = encodeURIComponent(path);
	const attempts = [
		path,
		`https://translate.google.com/translate?sl=de&tl=en&u=${encoded}`,
		`https://api.allorigins.win/raw?url=${encoded}`,
		`https://api.codetabs.com/v1/proxy?quest=${encoded}`
	];
	let last = "Hoster-URL nicht lesbar";
	for (const url of attempts) try {
		const res = await fetch(url, {
			headers: {
				...SS_HEADERS,
				Referer: `${ORIGIN}/`
			},
			redirect: "follow",
			signal: AbortSignal.timeout(12e3)
		});
		if (!res.ok) {
			last = `Redirect ${res.status}`;
			continue;
		}
		const html = await res.text();
		if (looksCaptcha(html)) {
			last = "Captcha";
			continue;
		}
		const embed = extractHosterUrl(html, res.url);
		if (embed && embed.startsWith("http")) {
			redirectCache.set(path, {
				url: embed,
				expires: Date.now() + REDIRECT_TTL
			});
			return embed;
		}
	} catch (e) {
		last = e instanceof Error ? e.message : last;
	}
	throw scrapeFail("hoster", last);
}
async function resolvePlay(redirectPath, hoster, lang, fresh = false) {
	const cacheKey = `${redirectPath}|${hoster}|${lang}`;
	if (!fresh) {
		const hit = playCache.get(cacheKey);
		if (hit && hit.expires > Date.now()) return hit.value;
	}
	const embedUrl = await followPlayUrl(redirectPath);
	const source = await extractFromHoster(embedUrl, hoster, lang);
	playCache.set(cacheKey, {
		value: source,
		expires: Date.now() + PLAY_TTL
	});
	return source;
}
async function resolveBestPlay(hosters, preferred, fresh = false) {
	const ordered = rankHosters(hosters, preferred);
	let last = "Kein spielbarer Hoster";
	for (const opt of ordered) try {
		return await resolvePlay(opt.redirectPath, opt.name, opt.lang, fresh);
	} catch (e) {
		last = e instanceof Error ? e.message : last;
	}
	throw scrapeFail("hoster", last.replace(/^[A-Z]+:/, ""));
}
//#endregion
export { getWatch, resolveBestPlay, resolvePlay };
