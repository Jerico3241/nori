import { r as createServerFn } from "./ssr.mjs";
import { t as createServerRpc } from "./createServerRpc-CcvdN_gc.mjs";
import { t as authMiddleware } from "./middleware-Bflz3Va7.mjs";
import { gn as object, hn as number, un as array, vn as record, yn as string } from "../_libs/@better-auth/core+[...].mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/account-library-BxfPlH7o.js
var progressSchema = object({
	slug: string(),
	title: string().optional().default(""),
	season: string().optional().default(""),
	episode: number().optional().default(0),
	episodePath: string().optional().default(""),
	germanTitle: string().optional().default(""),
	englishTitle: string().optional().default(""),
	positionSec: number().optional().default(0),
	durationSec: number().optional().default(0),
	updatedAt: number().optional().default(0),
	lang: string().optional()
});
var snapshotSchema = object({
	favorites: array(object({
		slug: string().min(1).max(180),
		title: string().max(220)
	})).max(400),
	progress: array(progressSchema).max(400),
	recents: array(object({
		slug: string(),
		title: string().optional().default(""),
		viewedAt: number().optional().default(0)
	})).max(40),
	titles: record(string(), string()).optional()
});
function asPayload(data) {
	return {
		v: 1,
		updatedAt: Date.now(),
		favorites: data.favorites.filter((f) => f.slug),
		progress: data.progress.filter((p) => p.slug && p.episodePath),
		recents: data.recents.filter((r) => r.slug),
		titles: data.titles ?? {}
	};
}
function parsePayload(raw) {
	let value = raw;
	if (typeof value === "string") try {
		value = JSON.parse(value);
	} catch {
		return null;
	}
	if (!value || typeof value !== "object") return null;
	const json = value;
	return {
		v: 1,
		updatedAt: typeof json.updatedAt === "number" ? json.updatedAt : Date.now(),
		favorites: Array.isArray(json.favorites) ? json.favorites.filter((f) => f?.slug) : [],
		progress: Array.isArray(json.progress) ? json.progress.filter((p) => p?.episodePath) : [],
		recents: Array.isArray(json.recents) ? json.recents.filter((r) => r?.slug) : [],
		titles: json.titles && typeof json.titles === "object" ? json.titles : {}
	};
}
var emptyLibrary = () => ({
	v: 1,
	updatedAt: 0,
	favorites: [],
	progress: [],
	recents: [],
	titles: {}
});
async function ensureTable() {
	const { getSql } = await import("./db-Czl8BUxo.mjs").then((n) => n.t).then((n) => n.t);
	const sql = await getSql();
	await sql.query(`
    create table if not exists nori_library (
      user_id text primary key,
      payload text not null,
      updated_at timestamptz not null default now()
    )
  `);
	return sql;
}
var pullAccountLibrary_createServerFn_handler = createServerRpc({
	id: "26be109a86abb080397abe35b4a110fd21047f8d4f378a83e7c2ebe5ff270b74",
	name: "pullAccountLibrary",
	filename: "src/lib/account-library.ts"
}, (opts) => pullAccountLibrary.__executeServer(opts));
var pullAccountLibrary = createServerFn({ method: "POST" }).middleware([authMiddleware]).handler(pullAccountLibrary_createServerFn_handler, async ({ context }) => {
	try {
		const rows = await (await ensureTable())`
        select payload from nori_library where user_id = ${context.userId} limit 1
      `;
		if (!rows[0]) return {
			ok: true,
			library: emptyLibrary()
		};
		return {
			ok: true,
			library: parsePayload(rows[0].payload) ?? emptyLibrary()
		};
	} catch (e) {
		return {
			ok: false,
			error: e instanceof Error ? e.message : "Lesen fehlgeschlagen"
		};
	}
});
var pushAccountLibrary_createServerFn_handler = createServerRpc({
	id: "9b362db42ffdd0e3ea4af055f9345246a720cdd1b8891dcbac410615d956775e",
	name: "pushAccountLibrary",
	filename: "src/lib/account-library.ts"
}, (opts) => pushAccountLibrary.__executeServer(opts));
var pushAccountLibrary = createServerFn({ method: "POST" }).middleware([authMiddleware]).validator(snapshotSchema).handler(pushAccountLibrary_createServerFn_handler, async ({ context, data }) => {
	const payload = asPayload(data);
	const body = JSON.stringify(payload);
	try {
		const sql = await ensureTable();
		try {
			await sql.query(`insert into nori_library (user_id, payload, updated_at)
           values ($1, $2, now())
           on conflict (user_id) do update set payload = excluded.payload, updated_at = now()`, [context.userId, body]);
		} catch {
			await sql.query(`insert into nori_library (user_id, payload, updated_at)
           values ($1, $2::jsonb, now())
           on conflict (user_id) do update set payload = excluded.payload, updated_at = now()`, [context.userId, body]);
		}
		return {
			ok: true,
			library: payload
		};
	} catch (e) {
		return {
			ok: false,
			error: e instanceof Error ? e.message : "Schreiben fehlgeschlagen"
		};
	}
});
//#endregion
export { pullAccountLibrary_createServerFn_handler, pushAccountLibrary_createServerFn_handler };
