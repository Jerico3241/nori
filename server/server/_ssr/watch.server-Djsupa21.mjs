import { n as scrapeFail } from "./errors-D28ORtyS.mjs";
import { r as resolveHosterRedirect } from "./http.server-D7YcQUwF.mjs";
import { t as load } from "../_libs/cheerio+[...].mjs";
import { a as toAniworldPath, n as fetchAniworldPage, o as unwrapTranslateUrl, r as fetchExternalPage, t as BROWSER_HEADERS } from "./scrape.server-Dx4-7B2O.mjs";
import { createHmac, randomBytes } from "node:crypto";
//#region node_modules/.nitro/vite/services/ssr/assets/watch.server-Djsupa21.js
var ORIGIN = "https://aniworld.to";
var LANG = {
	1: "DE",
	2: "EN",
	3: "GerSub"
};
var TOKEN_TTL = 12e4;
var TOKEN_SALT = process.env.NORI_STREAM_SECRET?.trim() || randomBytes(32).toString("hex");
var PLAY_TTL = 7e4;
var REDIRECT_TTL = 24e4;
var watchCache = /* @__PURE__ */ new Map();
var redirectCache = /* @__PURE__ */ new Map();
var playCache = /* @__PURE__ */ new Map();
var VOE_TOKENS = [
	"@$",
	"^^",
	"~@",
	"%?",
	"*~",
	"!!",
	"#&"
];
var HOST_RANK = {
	voe: 0,
	vidmoly: 1,
	vidoza: 2,
	lulustream: 3,
	luluvdo: 3,
	lulu: 3,
	speedfiles: 4,
	filemoon: 5,
	doodstream: 9,
	dood: 9
};
function hosterRank(name) {
	const n = name.toLowerCase().replace(/[^a-z]/g, "");
	for (const [key, rank] of Object.entries(HOST_RANK)) if (n.includes(key)) return rank;
	return 7;
}
function rankHosters(hosters, preferred) {
	const want = preferred?.toLowerCase() ?? "";
	return [...hosters].sort((a, b) => {
		return (want && a.name.toLowerCase() === want ? -1 : hosterRank(a.name)) - (want && b.name.toLowerCase() === want ? -1 : hosterRank(b.name));
	});
}
function isPrivateHost(host) {
	return host === "localhost" || host.endsWith(".local") || host.startsWith("127.") || host.startsWith("10.") || host.startsWith("192.168.") || /^172\.(1[6-9]|2\d|3[0-1])\./.test(host);
}
function isAllowedStreamUrl(raw) {
	try {
		const url = new URL(raw);
		if (url.protocol !== "https:") return false;
		if (isPrivateHost(url.hostname)) return false;
		const path = `${url.pathname}${url.search}`.toLowerCase();
		return path.includes(".m3u8") || path.includes(".mp4") || path.includes(".m4s") || path.includes(".ts") || path.includes("urlset") || path.includes("/hls") || path.includes("playlist");
	} catch {
		return false;
	}
}
function mintStreamToken(url) {
	if (!isAllowedStreamUrl(url)) throw scrapeFail("hoster", "Stream-URL nicht erlaubt");
	const body = JSON.stringify({
		u: url,
		e: Date.now() + TOKEN_TTL
	});
	const sig = createHmac("sha256", TOKEN_SALT).update(body).digest("base64url").slice(0, 20);
	return `${Buffer.from(body).toString("base64url")}.${sig}`;
}
function readStreamToken(id) {
	const dot = id.lastIndexOf(".");
	if (dot < 1) return null;
	const bodyB64 = id.slice(0, dot);
	const sig = id.slice(dot + 1);
	let body;
	try {
		body = Buffer.from(bodyB64, "base64url").toString("utf8");
	} catch {
		return null;
	}
	if (createHmac("sha256", TOKEN_SALT).update(body).digest("base64url").slice(0, 20) !== sig) return null;
	try {
		const parsed = JSON.parse(body);
		if (!parsed.u || typeof parsed.e !== "number" || parsed.e < Date.now()) return null;
		if (!isAllowedStreamUrl(parsed.u)) return null;
		return parsed.u;
	} catch {
		return null;
	}
}
function langLabel(key) {
	return LANG[key] || key;
}
function parseWatch(html, path) {
	const $ = load(html);
	const h1 = $("h1").first().text().replace(/\s+/g, " ").trim();
	const germanTitle = $(".seasonEpisodeTitle strong").first().text().trim() || $("h2").first().text().trim() || h1;
	const englishTitle = $(".seasonEpisodeTitle span").first().text().trim();
	const hosters = [];
	const seen = /* @__PURE__ */ new Set();
	const push = (redirectPath, langKey, name) => {
		const pathOnly = toAniworldPath(redirectPath) || redirectPath;
		if (!pathOnly.startsWith("/redirect/")) return;
		const key = `${pathOnly}|${langKey}`;
		if (seen.has(key)) return;
		seen.add(key);
		hosters.push({
			name: name.replace(/^Hoster\s+/i, "").trim() || "Hoster",
			lang: langLabel(langKey),
			langKey,
			redirectPath: pathOnly
		});
	};
	$("li[data-link-id]").each((_, el) => {
		const li = $(el);
		const id = li.attr("data-link-id") || "";
		const target = li.attr("data-link-target") || (id ? `/redirect/${id}` : "");
		const langKey = li.attr("data-lang-key") || "1";
		const name = li.find("h4").first().text().trim() || li.find("i.icon").attr("title") || "Hoster";
		push(target, langKey, name);
	});
	if (hosters.length === 0) $("a[href*='redirect']").each((_, a) => {
		const href = $(a).attr("href") || "";
		const langKey = $(a).closest("li").attr("data-lang-key") || "1";
		const name = $(a).find("h4").first().text().trim() || $(a).find("i.icon").attr("title") || "Hoster";
		push(href, langKey, name);
	});
	return {
		path,
		title: h1,
		germanTitle,
		englishTitle,
		hosters
	};
}
async function getWatch(path) {
	const clean = toAniworldPath(path) || path;
	if (!clean.startsWith("/anime/stream/")) throw scrapeFail("parse", "Ungültiger Pfad");
	const hit = watchCache.get(clean);
	if (hit && hit.expires > Date.now()) return hit.value;
	const info = parseWatch(await fetchAniworldPage(clean), clean);
	if (info.hosters.length === 0) throw scrapeFail("parse", "Keine Hoster gefunden");
	watchCache.set(clean, {
		value: info,
		expires: Date.now() + 6e5
	});
	return info;
}
function rot13(input) {
	let out = "";
	for (const ch of input) {
		const code = ch.charCodeAt(0);
		if (code >= 65 && code <= 90) out += String.fromCharCode((code - 65 + 13) % 26 + 65);
		else if (code >= 97 && code <= 122) out += String.fromCharCode((code - 97 + 13) % 26 + 97);
		else out += ch;
	}
	return out;
}
function decodeVoePayload(encrypted) {
	try {
		let s = rot13(encrypted);
		for (const token of VOE_TOKENS) s = s.replaceAll(token, "_");
		s = s.replaceAll("_", "");
		const first = Buffer.from(s, "base64").toString("latin1");
		const reversed = Array.from(first, (c) => String.fromCharCode(c.charCodeAt(0) - 3)).join("").split("").reverse().join("");
		const json = Buffer.from(reversed, "base64").toString("utf8");
		const parsed = JSON.parse(json);
		return parsed && typeof parsed === "object" ? parsed : null;
	} catch {
		return null;
	}
}
function extractVoeConfig(html) {
	const matches = html.matchAll(/<script[^>]*type=["']application\/json["'][^>]*>([\s\S]*?)<\/script>/gi);
	for (const match of matches) try {
		const parsed = JSON.parse(match[1].trim());
		const blob = Array.isArray(parsed) && typeof parsed[0] === "string" ? parsed[0] : null;
		if (!blob) continue;
		const cfg = decodeVoePayload(blob);
		if (!cfg) continue;
		const source = typeof cfg.source === "string" ? cfg.source : void 0;
		const direct = typeof cfg.direct_access_url === "string" ? cfg.direct_access_url : void 0;
		if (source || direct) return {
			source,
			direct
		};
	} catch {}
	return null;
}
function extractBounce(html) {
	for (const re of [/window\.location\.href\s*=\s*['"](https?:\/\/[^'"]+\/e\/[A-Za-z0-9]+)['"]/i, /location\.href\s*=\s*['"](https?:\/\/[^'"]+\/e\/[A-Za-z0-9]+)['"]/i]) {
		const m = html.match(re);
		if (m?.[1] && !m[1].includes("translate.goog") && !m[1].includes("voe.sx")) return m[1];
	}
	const any = html.match(/window\.location\.href\s*=\s*['"](https?:\/\/[^'"]+)['"]/i);
	if (any?.[1] && !any[1].includes("translate") && !any[1].includes("voe.sx/api")) return any[1];
	return null;
}
function extractEmbedFromTranslate(html, finalUrl) {
	const bounce = extractBounce(html);
	if (bounce) return bounce;
	const source = html.match(/data-source-url=["'](https?:\/\/[^"']+)["']/i)?.[1] || html.match(/<base href=["'](https?:\/\/[^"']+)["']/i)?.[1];
	if (source && !source.includes("aniworld.to") && !source.includes("translate.google")) {
		const bounced = extractBounce(html);
		if (bounced) return bounced;
		return unwrapTranslateUrl(source);
	}
	const unwrapped = unwrapTranslateUrl(finalUrl);
	if (unwrapped && !unwrapped.includes("aniworld.to") && !unwrapped.includes("translate.google")) return unwrapped;
	return null;
}
function looksCaptcha(html) {
	const h = html.slice(0, 4e3).toLowerCase();
	return h.includes("cf-turnstile") || h.includes("g-recaptcha") || h.includes("hcaptcha") || h.includes("just a moment") || h.includes("ddos-guard");
}
async function followRedirect(redirectPath) {
	const path = toAniworldPath(redirectPath) || redirectPath;
	if (!path.startsWith("/redirect/")) throw scrapeFail("hoster", "Ungültiger Hoster");
	const hit = redirectCache.get(path);
	if (hit && hit.expires > Date.now()) return hit.url;
	const target = `${ORIGIN}${path}`;
	try {
		const direct = await resolveHosterRedirect(target, `${ORIGIN}/`);
		if (direct) {
			redirectCache.set(path, {
				url: direct,
				expires: Date.now() + REDIRECT_TTL
			});
			return direct;
		}
	} catch {}
	const encoded = encodeURIComponent(target);
	const attempts = [
		`https://translate.google.com/translate?sl=de&tl=en&u=${encoded}`,
		`https://api.allorigins.win/raw?url=${encoded}`,
		`https://api.codetabs.com/v1/proxy?quest=${encoded}`
	];
	let last = "Hoster-URL nicht lesbar";
	for (const url of attempts) try {
		const res = await fetch(url, {
			headers: BROWSER_HEADERS,
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
		const embed = extractEmbedFromTranslate(html, res.url);
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
function toEmbedUrl(url, hoster) {
	const n = hoster.toLowerCase();
	if (n.includes("filemoon") || n.includes("vidmoly") || n.includes("dood")) return url.replace(/\/d\//, "/e/").replace(/\/v\//, "/e/");
	return url;
}
function firstMediaUrl(html) {
	const hls = html.match(/file\s*[:=]\s*["'](https:[^"']+\.m3u8[^"']*)["']/i)?.[1] || html.match(/src\s*[:=]\s*["'](https:[^"']+\.m3u8[^"']*)["']/i)?.[1] || html.match(/["'](https:[^"']+\.m3u8[^"']*)["']/i)?.[1];
	if (hls && isAllowedStreamUrl(hls)) return {
		kind: "hls",
		url: hls
	};
	const mp4 = html.match(/file\s*[:=]\s*["'](https:[^"']+\.mp4[^"']*)["']/i)?.[1] || html.match(/["'](https:[^"']+\.mp4[^"']*)["']/i)?.[1];
	if (mp4 && isAllowedStreamUrl(mp4) && !mp4.includes("test-videos.co.uk")) return {
		kind: "mp4",
		url: mp4
	};
	return null;
}
function playFromVoe(cfg, hoster, lang) {
	if (cfg.source && cfg.source.includes(".m3u8") && isAllowedStreamUrl(cfg.source)) return {
		kind: "hls",
		url: cfg.source,
		proxied: `/api/hls?t=${mintStreamToken(cfg.source)}`,
		hoster,
		lang
	};
	if (cfg.direct && isAllowedStreamUrl(cfg.direct)) return {
		kind: "mp4",
		url: cfg.direct,
		proxied: `/api/hls?t=${mintStreamToken(cfg.direct)}`,
		hoster,
		lang
	};
	if (cfg.source && cfg.source.includes(".mp4") && isAllowedStreamUrl(cfg.source)) return {
		kind: "mp4",
		url: cfg.source,
		proxied: `/api/hls?t=${mintStreamToken(cfg.source)}`,
		hoster,
		lang
	};
	return null;
}
async function extractFromHoster(embedUrl, hoster, lang) {
	const pageUrl = toEmbedUrl(embedUrl, hoster);
	let html = "";
	try {
		html = await fetchExternalPage(pageUrl, pageUrl);
	} catch {
		throw scrapeFail("hoster", `${hoster} nicht erreichbar`);
	}
	if (looksCaptcha(html)) throw scrapeFail("hoster", `${hoster}: Captcha`);
	const bounce = extractBounce(html);
	if (bounce && bounce !== pageUrl) {
		try {
			html = await fetchExternalPage(bounce, pageUrl);
		} catch {
			throw scrapeFail("hoster", `${hoster} Redirect fehlgeschlagen`);
		}
		if (looksCaptcha(html)) throw scrapeFail("hoster", `${hoster}: Captcha`);
	}
	const voe = extractVoeConfig(html);
	if (voe) {
		const play = playFromVoe(voe, hoster, lang);
		if (play) return play;
	}
	const media = firstMediaUrl(html);
	if (media) return {
		kind: media.kind,
		url: media.url,
		proxied: `/api/hls?t=${mintStreamToken(media.url)}`,
		hoster,
		lang
	};
	throw scrapeFail("hoster", `${hoster} liefert keinen Stream`);
}
async function resolvePlay(redirectPath, hoster, lang, fresh = false) {
	const path = toAniworldPath(redirectPath) || redirectPath;
	const cacheKey = `${path}|${hoster}|${lang}`;
	if (!fresh) {
		const hit = playCache.get(cacheKey);
		if (hit && hit.expires > Date.now()) return hit.value;
	}
	const source = await extractFromHoster(await followRedirect(path), hoster, lang);
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
export { extractFromHoster, getWatch, mintStreamToken, rankHosters, readStreamToken, resolveBestPlay, resolvePlay };
