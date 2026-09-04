//#region node_modules/.nitro/vite/services/ssr/assets/http.server-D7YcQUwF.js
var jars = /* @__PURE__ */ new Map();
var BROWSER_HEADERS = {
	"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
	Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
	"Accept-Language": "de-DE,de;q=0.9,en;q=0.8"
};
function originOf(url) {
	try {
		return new URL(url).origin;
	} catch {
		return "";
	}
}
function putCookies(url, headers) {
	const origin = originOf(url);
	if (!origin) return;
	let bag = jars.get(origin);
	if (!bag) {
		bag = /* @__PURE__ */ new Map();
		jars.set(origin, bag);
	}
	const cookies = typeof headers.getSetCookie === "function" ? headers.getSetCookie() : [];
	for (const raw of cookies) {
		const pair = raw.split(";")[0] || "";
		const eq = pair.indexOf("=");
		if (eq < 1) continue;
		const name = pair.slice(0, eq).trim();
		const value = pair.slice(eq + 1).trim();
		if (!name) continue;
		if (/expires|max-age|path|domain|samesite|secure|httponly/i.test(name)) continue;
		bag.set(name, value);
	}
}
function cookieHeaderFor(url) {
	const bag = jars.get(originOf(url));
	if (!bag?.size) return "";
	return [...bag].map(([k, v]) => `${k}=${v}`).join("; ");
}
async function fetchOrigin(url, opts) {
	const headers = {
		...BROWSER_HEADERS,
		...opts?.accept ? { Accept: opts.accept } : {},
		...opts?.referer ? { Referer: opts.referer } : {},
		...opts?.headers ?? {}
	};
	const cookie = cookieHeaderFor(url);
	if (cookie) headers.Cookie = cookie;
	const timeout = AbortSignal.timeout(opts?.timeout ?? 12e3);
	const signal = opts?.extra ? AbortSignal.any([timeout, opts.extra]) : timeout;
	const res = await fetch(url, {
		headers,
		redirect: opts?.redirect ?? "follow",
		signal
	});
	putCookies(url, res.headers);
	if (res.url && res.url !== url) putCookies(res.url, res.headers);
	return res;
}
function looksDdos(html) {
	const head = html.slice(0, 900).toLowerCase();
	return head.includes("ddos-guard") || head.includes("just a moment") || head.includes("cf-turnstile") || head.includes("hcaptcha") || html.length < 900 && head.includes("<title>ddos");
}
function firstLocation(res, base) {
	const loc = res.headers.get("location");
	if (!loc) return null;
	try {
		return new URL(loc, base).toString();
	} catch {
		return loc.startsWith("http") ? loc : null;
	}
}
function isExternalHoster(url) {
	try {
		const u = new URL(url);
		if (u.protocol !== "https:") return false;
		const h = u.hostname.toLowerCase();
		if (h.includes("aniworld.")) return false;
		if (h.includes("serienstream.")) return false;
		if (h === "s.to" || h.endsWith(".s.to")) return false;
		if (h.includes("translate.google") || h.includes("translate.goog")) return false;
		if (h.includes("allorigins.") || h.includes("codetabs.")) return false;
		return true;
	} catch {
		return false;
	}
}
async function resolveHosterRedirect(absoluteUrl, referer) {
	const res = await fetchOrigin(absoluteUrl, {
		redirect: "manual",
		referer,
		timeout: 12e3
	});
	if (res.status >= 300 && res.status < 400) {
		const loc = firstLocation(res, absoluteUrl);
		if (!loc) return null;
		if (isExternalHoster(loc)) return loc;
		if (loc.split("?")[0] === absoluteUrl.split("?")[0]) return null;
		return resolveHosterRedirect(loc, referer);
	}
	if (!res.ok) return null;
	const html = await res.text();
	if (looksDdos(html)) return null;
	const bounce = html.match(/window\.location(?:\.href)?\s*=\s*['"](https?:\/\/[^'"]+)['"]/i)?.[1] || html.match(/location\.replace\(\s*['"](https?:\/\/[^'"]+)['"]/i)?.[1] || html.match(/<iframe[^>]+src=["'](https?:\/\/[^"']+)["']/i)?.[1];
	if (bounce && isExternalHoster(bounce)) return bounce;
	return null;
}
//#endregion
export { looksDdos as n, resolveHosterRedirect as r, fetchOrigin as t };
