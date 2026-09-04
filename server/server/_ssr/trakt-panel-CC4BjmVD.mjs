import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { t as Button } from "./button-6GLc1whh.mjs";
import { a as pullTraktWatched, i as pullPublicWatched, l as useTrakt, n as isTraktConnected, o as startDeviceAuth, r as pollDeviceToken, s as traktServerCaps, t as ingestTraktExport } from "./trakt-wm9BT4pC.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/trakt-panel-CC4BjmVD.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
function formatResult(result) {
	const extra = result.unmatched ? ` ${result.unmatched} Titel nicht im Katalog.` : "";
	return `Übernommen: ${result.shows} Serien, ${result.episodes} Folgen.${extra}`;
}
function TraktPanel() {
	const storedUser = useTrakt((s) => s.username);
	const lastSyncAt = useTrakt((s) => s.lastSyncAt);
	const accessToken = useTrakt((s) => s.accessToken);
	const clientId = useTrakt((s) => s.clientId);
	const clientSecret = useTrakt((s) => s.clientSecret);
	const setCredentials = useTrakt((s) => s.setCredentials);
	const setUsername = useTrakt((s) => s.setUsername);
	const disconnect = useTrakt((s) => s.disconnect);
	const [username, setUserField] = (0, import_react.useState)(storedUser);
	const [id, setId] = (0, import_react.useState)(clientId);
	const [secret, setSecret] = (0, import_react.useState)(clientSecret);
	const [paste, setPaste] = (0, import_react.useState)("");
	const [caps, setCaps] = (0, import_react.useState)({
		serverApp: false,
		hasClientId: false
	});
	const [busy, setBusy] = (0, import_react.useState)(false);
	const [status, setStatus] = (0, import_react.useState)("");
	const [code, setCode] = (0, import_react.useState)(null);
	(0, import_react.useEffect)(() => {
		traktServerCaps().then(setCaps);
	}, []);
	(0, import_react.useEffect)(() => {
		setUserField(storedUser);
		setId(clientId);
		setSecret(clientSecret);
	}, [
		storedUser,
		clientId,
		clientSecret
	]);
	(0, import_react.useEffect)(() => {
		if (!code) return;
		let stop = false;
		let wait = code.interval * 1e3;
		const tick = async () => {
			if (stop) return;
			if (Date.now() > code.until) {
				setCode(null);
				setStatus("Code abgelaufen. Nochmal verbinden.");
				return;
			}
			try {
				const state = await pollDeviceToken(code.deviceCode);
				if (stop) return;
				if (state === "done") {
					setCode(null);
					setBusy(true);
					setStatus("Verbunden. Lade gesehenen Verlauf…");
					try {
						const result = await pullTraktWatched();
						setStatus(formatResult(result));
					} catch (e) {
						setStatus(e instanceof Error ? e.message : "Sync fehlgeschlagen, Verbindung steht.");
					} finally {
						setBusy(false);
					}
					return;
				}
				if (state === "denied") {
					setCode(null);
					setStatus("Freigabe abgelehnt.");
					return;
				}
				if (state === "expired") {
					setCode(null);
					setStatus("Code abgelaufen.");
					return;
				}
				if (state === "slow") wait = Math.min(wait + 1e3, 8e3);
			} catch (e) {
				setCode(null);
				setStatus(e instanceof Error ? e.message : "Trakt-Fehler");
				return;
			}
			window.setTimeout(() => void tick(), wait);
		};
		const t = window.setTimeout(() => void tick(), wait);
		return () => {
			stop = true;
			window.clearTimeout(t);
		};
	}, [code]);
	const oauth = Boolean(accessToken) || isTraktConnected();
	async function importText(raw) {
		setBusy(true);
		setStatus("Importiere Verlauf…");
		try {
			const result = await ingestTraktExport(raw);
			setPaste("");
			setStatus(formatResult(result));
		} catch (e) {
			setStatus(e instanceof Error ? e.message : "Import fehlgeschlagen.");
		} finally {
			setBusy(false);
		}
	}
	async function onFile(e) {
		const file = e.target.files?.[0];
		e.target.value = "";
		if (!file) return;
		setBusy(true);
		try {
			await importText(await file.text());
		} catch (err) {
			setStatus(err instanceof Error ? err.message : "Datei nicht lesbar.");
			setBusy(false);
		}
	}
	async function loadProfile() {
		const name = username.trim();
		if (!name) {
			setStatus("Benutzername eintragen.");
			return;
		}
		if (id.trim()) setCredentials(id.trim(), secret);
		setBusy(true);
		setStatus("Lade öffentliches Profil…");
		try {
			const result = await pullPublicWatched(name);
			setStatus(formatResult(result));
		} catch (e) {
			setUsername(name);
			setStatus(e instanceof Error ? e.message : "Profil nicht lesbar.");
		} finally {
			setBusy(false);
		}
	}
	async function connectOauth() {
		setBusy(true);
		setStatus("");
		try {
			if (!caps.serverApp) {
				if (!id.trim() || !secret.trim()) {
					setStatus("Client-ID und Secret von einer VIP-App eintragen.");
					return;
				}
				setCredentials(id.trim(), secret.trim());
			} else if (id.trim() || secret.trim()) setCredentials(id.trim(), secret.trim());
			const started = await startDeviceAuth();
			setCode({
				userCode: started.userCode,
				url: started.verificationUrl,
				deviceCode: started.deviceCode,
				interval: started.interval,
				until: Date.now() + started.expiresIn * 1e3
			});
			setStatus("Code auf Trakt eingeben und die App freigeben.");
		} catch (e) {
			setStatus(e instanceof Error ? e.message : "Verbinden fehlgeschlagen.");
		} finally {
			setBusy(false);
		}
	}
	async function syncOauth() {
		setBusy(true);
		setStatus("Gleiche mit Trakt ab…");
		try {
			const result = await pullTraktWatched();
			setStatus(formatResult(result));
		} catch (e) {
			setStatus(e instanceof Error ? e.message : "Sync fehlgeschlagen.");
		} finally {
			setBusy(false);
		}
	}
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
		className: "rounded-xl bg-surface p-5 shadow-[var(--shadow-border)]",
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h2", {
				className: "font-display text-lg tracking-tight",
				children: "Trakt"
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
				className: "mt-2 text-sm leading-relaxed text-muted",
				children: "Neue API-Apps bei Trakt sind VIP-only. Nori holt den Verlauf deshalb per Export — ohne Anmeldung bei Trakt. Zurückschreiben geht nur, wenn du schon eine alte App-ID hast."
			}),
			lastSyncAt || storedUser ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
				className: "mt-3 text-sm",
				children: [storedUser ? `Profil: ${storedUser}. ` : null, lastSyncAt ? `Letzter Import ${new Date(lastSyncAt).toLocaleString("de-DE")}.` : null]
			}) : null,
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "mt-4 space-y-3",
				children: [
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "text-xs uppercase tracking-widest text-muted",
						children: "1. Verlauf importieren"
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
						className: "text-sm leading-relaxed text-muted",
						children: [
							"Auf ",
							/* @__PURE__ */ (0, import_jsx_runtime.jsx)("a", {
								href: "https://trakt.tv/settings/data",
								target: "_blank",
								rel: "noreferrer",
								className: "underline-offset-2 hover:underline",
								children: "trakt.tv/settings/data"
							}),
							" JSON oder CSV exportieren und hier ablegen."
						]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
						className: "inline-flex h-11 cursor-pointer items-center rounded-md bg-elevated px-4 text-sm",
						children: ["Datei wählen", /* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							type: "file",
							accept: ".json,.csv,application/json,text/csv,text/plain",
							className: "hidden",
							onChange: onFile
						})]
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("textarea", {
						value: paste,
						onChange: (e) => setPaste(e.target.value),
						placeholder: "Oder JSON hier einfügen",
						rows: 4,
						spellCheck: false,
						className: "w-full rounded-md bg-elevated px-3 py-2 text-sm outline-none"
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
						variant: "outline",
						disabled: busy || !paste.trim(),
						onClick: () => void importText(paste),
						children: busy ? "Importiere…" : "Einfügen übernehmen"
					})
				]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "mt-6 space-y-3",
				children: [
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "text-xs uppercase tracking-widest text-muted",
						children: "2. Öffentliches Profil"
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "text-sm leading-relaxed text-muted",
						children: "Nur wenn das Profil öffentlich ist und ein API-Key existiert (Server oder alte Client-ID). Sonst den Export nutzen."
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
						className: "block",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
							className: "text-xs uppercase tracking-widest text-muted",
							children: "Benutzername"
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							value: username,
							onChange: (e) => setUserField(e.target.value),
							autoComplete: "off",
							spellCheck: false,
							placeholder: "trakt-username",
							className: "mt-1 h-11 w-full rounded-md bg-elevated px-3 text-sm outline-none"
						})]
					}),
					!caps.hasClientId ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
						className: "block",
						children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
							className: "text-xs uppercase tracking-widest text-muted",
							children: "Client-ID (optional)"
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
							value: id,
							onChange: (e) => setId(e.target.value),
							autoComplete: "off",
							spellCheck: false,
							className: "mt-1 h-11 w-full rounded-md bg-elevated px-3 text-sm outline-none"
						})]
					}) : null,
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
						variant: "outline",
						disabled: busy,
						onClick: () => void loadProfile(),
						children: busy ? "Lade…" : "Profil übernehmen"
					})
				]
			}),
			oauth ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "mt-6 rounded-lg bg-elevated p-4",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("p", {
					className: "text-sm",
					children: [
						"OAuth aktiv",
						storedUser ? ` als ${storedUser}` : "",
						". Schreiben zu Trakt ist an."
					]
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
					className: "mt-3 flex flex-wrap gap-2",
					children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
						variant: "outline",
						disabled: busy,
						onClick: () => void syncOauth(),
						children: busy ? "Gleiche ab…" : "Jetzt abgleichen"
					}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
						variant: "ghost",
						disabled: busy,
						onClick: () => {
							disconnect();
							setCode(null);
							setStatus("Getrennt.");
						},
						children: "Trennen"
					})]
				})]
			}) : /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("details", {
				className: "mt-6",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("summary", {
					className: "cursor-pointer text-sm text-muted",
					children: "VIP: OAuth, um zu Trakt zu schreiben"
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
					className: "mt-3 space-y-3",
					children: [
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
							className: "text-sm leading-relaxed text-muted",
							children: "Nur nötig, wenn Nori fertige Folgen zurück zu Trakt schicken soll. Neue Apps kann seit 2026 nur VIP anlegen."
						}),
						!caps.serverApp ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_jsx_runtime.Fragment, { children: [/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
							className: "block",
							children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
								className: "text-xs uppercase tracking-widest text-muted",
								children: "Client-ID"
							}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
								value: id,
								onChange: (e) => setId(e.target.value),
								autoComplete: "off",
								spellCheck: false,
								className: "mt-1 h-11 w-full rounded-md bg-elevated px-3 text-sm outline-none"
							})]
						}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
							className: "block",
							children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
								className: "text-xs uppercase tracking-widest text-muted",
								children: "Client-Secret"
							}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
								value: secret,
								onChange: (e) => setSecret(e.target.value),
								type: "password",
								autoComplete: "off",
								spellCheck: false,
								className: "mt-1 h-11 w-full rounded-md bg-elevated px-3 text-sm outline-none"
							})]
						})] }) : null,
						code ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
							className: "rounded-lg bg-elevated p-4 text-center",
							children: [
								/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
									className: "text-xs uppercase tracking-widest text-muted",
									children: "Code auf Trakt eingeben"
								}),
								/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
									className: "mt-2 font-mono text-3xl tracking-widest text-fg",
									children: code.userCode
								}),
								/* @__PURE__ */ (0, import_jsx_runtime.jsx)("a", {
									href: code.url,
									target: "_blank",
									rel: "noreferrer",
									className: "mt-3 inline-flex h-11 items-center text-sm text-muted hover:text-fg",
									children: code.url.replace(/^https?:\/\//, "")
								})
							]
						}) : /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
							variant: "outline",
							disabled: busy,
							onClick: () => void connectOauth(),
							children: busy ? "Bitte warten…" : "Mit Trakt verbinden"
						})
					]
				})]
			}),
			status ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
				className: "mt-3 text-sm text-muted",
				children: status
			}) : null
		]
	});
}
//#endregion
export { TraktPanel as t };
