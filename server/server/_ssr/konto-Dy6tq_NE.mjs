import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { v as Link, y as Navigate } from "../_libs/@tanstack/react-router+[...].mjs";
import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { i as hasGateSessionMarker } from "./server-DR24G2td.mjs";
import { i as signOut, r as signIn } from "./client-C_SNNFs7.mjs";
import { D as useCurrentUserState, E as isPlaceholderAccount, O as continueWatching, T as accountLabel, v as useDriveStatus, w as accountEmail, z as useLibrary } from "./router-DDQw7P_P.mjs";
import { t as BackButton } from "./back-button-0P2iyjug.mjs";
import { t as Button } from "./button-6GLc1whh.mjs";
import { t as TraktPanel } from "./trakt-panel-CC4BjmVD.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/konto-Dy6tq_NE.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
/**
* Auth state components — plain wrappers around `useCurrentUserState()`.
*
* With auth on, visitors are signed out until they authenticate — in the sandbox
* live preview too, which does real sign-in. The shared dev user appears only
* when auth is disabled (`VITE_AUTH_ENABLED=false`, the shipped default).
* While the session is still resolving, gates that care about signed-out state
* render nothing so there's no signed-out flash on hard reload.
*/
/** Where `RedirectToSignIn` sends signed-out visitors. Create this route. */
var SIGN_IN_PATH = "/login";
/**
* Client-side redirect to the sign-in route (TanStack `<Navigate>` — NOT a full
* `window.location` reload). A hard navigation re-bootstraps the SPA and re-runs
* session loading, which feels like a second "Loading…" on /login.
*
* Guard routes by waiting out `isPending` first (see `use-current-user`), then
* render this.
*/
function RedirectToSignIn({ to = SIGN_IN_PATH }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Navigate, { to });
}
var subscribeToNothing = () => () => {};
function Konto() {
	const { user, isPending } = useCurrentUserState();
	const favorites = useLibrary((s) => s.favorites);
	const progress = useLibrary((s) => s.progress);
	const continues = continueWatching(progress);
	const { status, syncing, syncNow } = useDriveStatus();
	const [signingOut, setSigningOut] = (0, import_react.useState)(false);
	const [linking, setLinking] = (0, import_react.useState)(false);
	const gateSession = (0, import_react.useSyncExternalStore)(subscribeToNothing, hasGateSessionMarker, () => false);
	if (isPending) return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("main", {
		className: "mx-auto max-w-lg px-4 py-12",
		children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "h-64 animate-pulse rounded-xl bg-surface" })
	});
	if (!user) return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(RedirectToSignIn, {});
	const label = accountLabel(user);
	const email = accountEmail(user);
	const placeholder = isPlaceholderAccount(user);
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("main", {
		className: "mx-auto max-w-lg px-4 pb-20 pt-6",
		children: [
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)(BackButton, { fallback: "/einstellungen" }),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
				className: "mt-4 text-xs font-medium uppercase tracking-widest text-muted",
				children: "Konto"
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h1", {
				className: "mt-2 font-display text-3xl tracking-display",
				children: "Dein Account"
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
				className: "mt-8 flex items-center gap-4 rounded-xl bg-surface p-5 shadow-[var(--shadow-border)]",
				children: [user.profileImageUrl && !placeholder ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("img", {
					src: user.profileImageUrl,
					alt: "",
					className: "size-14 rounded-full object-cover"
				}) : /* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
					className: "grid size-14 place-items-center rounded-full bg-elevated font-display text-2xl",
					children: label.slice(0, 1).toUpperCase()
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
					className: "min-w-0",
					children: [
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
							className: "truncate font-display text-xl tracking-tight",
							children: label
						}),
						email ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
							className: "truncate text-sm text-muted",
							children: email
						}) : null,
						placeholder ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
							className: "mt-1 text-sm text-muted",
							children: "Noch nicht mit Google verbunden."
						}) : null
					]
				})]
			}),
			placeholder ? /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
				className: "mt-4 rounded-xl bg-surface p-5 shadow-[var(--shadow-border)]",
				children: [
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h2", {
						className: "font-display text-lg tracking-tight",
						children: "Mit Google anmelden"
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "mt-2 text-sm leading-relaxed text-muted",
						children: "Dann liegen Merkliste und Fortschritt in deinem Drive, und hier steht dein Name statt einem Platzhalter."
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
						className: "mt-4",
						disabled: linking,
						onClick: () => {
							setLinking(true);
							signIn("grok-google", {
								callbackURL: "/konto",
								errorCallbackURL: "/login"
							}).catch(() => setLinking(false));
						},
						children: linking ? "Bitte warten…" : "Weiter mit Google"
					})
				]
			}) : null,
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
				className: "mt-4 grid grid-cols-2 gap-3",
				children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Stat, {
					label: "Merkliste",
					value: String(favorites.length)
				}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Stat, {
					label: "Weiter schauen",
					value: String(continues.length)
				})]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("section", {
				className: "mt-4 rounded-xl bg-surface p-5 shadow-[var(--shadow-border)]",
				children: [
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h2", {
						className: "font-display text-lg tracking-tight",
						children: "Speicher"
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "mt-2 text-sm leading-relaxed text-muted",
						children: "Merkliste, Verlauf und die Stelle in der Folge werden automatisch gesichert, sobald du angemeldet bist. Andere Geräte laden denselben Stand beim Öffnen und etwa alle 20 Sekunden."
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
						className: "mt-3 text-sm text-fg",
						children: status
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
						className: "mt-4",
						variant: "outline",
						disabled: syncing,
						onClick: () => void syncNow(),
						children: syncing ? "Gleiche ab…" : "Jetzt abgleichen"
					})
				]
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", {
				className: "mt-4",
				children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(TraktPanel, {})
			}),
			/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
				className: "mt-8 flex flex-wrap items-center gap-3",
				children: [
					!gateSession ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
						variant: "outline",
						disabled: signingOut,
						onClick: () => {
							setSigningOut(true);
							signOut().catch(() => setSigningOut(false));
						},
						children: signingOut ? "Abmelden…" : "Abmelden"
					}) : null,
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Link, {
						to: "/einstellungen",
						className: "inline-flex h-11 items-center text-sm text-muted hover:text-fg",
						children: "Einstellungen"
					}),
					/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Link, {
						to: "/",
						className: "inline-flex h-11 items-center text-sm text-muted hover:text-fg",
						children: "Zur Startseite"
					})
				]
			})
		]
	});
}
function Stat({ label, value }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
		className: "rounded-xl bg-surface p-5 shadow-[var(--shadow-border)]",
		children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
			className: "text-xs font-medium uppercase tracking-widest text-muted",
			children: label
		}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
			className: "mt-2 font-display text-3xl tracking-display",
			children: value
		})]
	});
}
//#endregion
export { Konto as component };
