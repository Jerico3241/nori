import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { b as useNavigate, v as Link, y as Navigate } from "../_libs/@tanstack/react-router+[...].mjs";
import { i as require_jsx_runtime } from "../_libs/react+tanstack__react-query.mjs";
import { r as signIn, t as authClient } from "./client-C_SNNFs7.mjs";
import { D as useCurrentUserState, E as isPlaceholderAccount } from "./router-DDQw7P_P.mjs";
import { t as Button } from "./button-6GLc1whh.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/login-sroey2Lr.js
var import_react = /* @__PURE__ */ __toESM(require_react());
var import_jsx_runtime = require_jsx_runtime();
function Login() {
	const { user, isPending } = useCurrentUserState();
	const navigate = useNavigate();
	const [mode, setMode] = (0, import_react.useState)("in");
	const [name, setName] = (0, import_react.useState)("");
	const [email, setEmail] = (0, import_react.useState)("");
	const [password, setPassword] = (0, import_react.useState)("");
	const [busy, setBusy] = (0, import_react.useState)(false);
	const [error, setError] = (0, import_react.useState)(null);
	const realUser = user && !isPlaceholderAccount(user);
	if (isPending) return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("main", {
		className: "mx-auto grid min-h-[calc(100dvh-4rem)] max-w-md place-items-center px-4",
		children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("div", { className: "h-48 w-full animate-pulse rounded-xl bg-surface" })
	});
	if (realUser) return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Navigate, { to: "/konto" });
	async function google() {
		setError(null);
		setBusy(true);
		try {
			await signIn("grok-google", {
				callbackURL: "/konto",
				errorCallbackURL: "/login"
			});
		} catch (e) {
			setError(e instanceof Error ? e.message : "Google-Anmeldung fehlgeschlagen. Pop-ups erlauben und nochmal.");
			setBusy(false);
		}
	}
	async function submit(e) {
		e.preventDefault();
		setError(null);
		setBusy(true);
		try {
			if (mode === "up") {
				const { error: err } = await authClient.signUp.email({
					email,
					password,
					name: name.trim() || email.split("@")[0] || "Nori"
				});
				if (err) throw new Error(err.message || "Konto konnte nicht erstellt werden.");
			} else {
				const { error: err } = await authClient.signIn.email({
					email,
					password
				});
				if (err) throw new Error(err.message || "E-Mail oder Passwort stimmt nicht.");
			}
			await authClient.getSession();
			await navigate({ to: "/konto" });
		} catch (err) {
			setError(err instanceof Error ? err.message : "Das hat nicht geklappt.");
		} finally {
			setBusy(false);
		}
	}
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("main", {
		className: "mx-auto grid min-h-[calc(100dvh-4rem)] max-w-md place-items-center px-4 py-12",
		children: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
			className: "w-full rounded-xl bg-surface p-6 shadow-[var(--shadow-border)]",
			children: [
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "text-xs font-medium uppercase tracking-widest text-muted",
					children: "Konto"
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("h1", {
					className: "mt-2 font-display text-3xl tracking-display",
					children: "Anmelden"
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
					className: "mt-2 text-sm text-muted",
					children: "Mit Google oder E-Mail. Merkliste und Fortschritt bleiben lokal und gehen in dein Drive, sobald verbunden."
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
					className: "mt-6 w-full",
					disabled: busy || false,
					onClick: () => void google(),
					children: busy ? "Google öffnet…" : "Weiter mit Google"
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
					className: "my-6 flex items-center gap-3 text-xs uppercase tracking-widest text-subtle",
					children: [
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { className: "h-px flex-1 bg-fg/10" }),
						"oder E-Mail",
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", { className: "h-px flex-1 bg-fg/10" })
					]
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("div", {
					className: "mb-4 flex gap-1 rounded-md bg-elevated p-1",
					children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)(ModeTab, {
						active: mode === "in",
						onClick: () => setMode("in"),
						children: "Anmelden"
					}), /* @__PURE__ */ (0, import_jsx_runtime.jsx)(ModeTab, {
						active: mode === "up",
						onClick: () => setMode("up"),
						children: "Konto erstellen"
					})]
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsxs)("form", {
					className: "space-y-3",
					onSubmit: (e) => void submit(e),
					children: [
						mode === "up" ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)(Field, {
							label: "Name",
							children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
								value: name,
								onChange: (e) => setName(e.target.value),
								autoComplete: "name",
								className: fieldClass
							})
						}) : null,
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Field, {
							label: "E-Mail",
							children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
								type: "email",
								required: true,
								value: email,
								onChange: (e) => setEmail(e.target.value),
								autoComplete: "email",
								className: fieldClass
							})
						}),
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Field, {
							label: "Passwort",
							children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)("input", {
								type: "password",
								required: true,
								minLength: 8,
								value: password,
								onChange: (e) => setPassword(e.target.value),
								autoComplete: mode === "up" ? "new-password" : "current-password",
								className: fieldClass
							})
						}),
						error ? /* @__PURE__ */ (0, import_jsx_runtime.jsx)("p", {
							className: "text-sm text-muted",
							children: error
						}) : null,
						/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Button, {
							className: "w-full",
							type: "submit",
							disabled: busy || false,
							children: busy ? "Bitte warten…" : mode === "up" ? "Konto erstellen" : "Anmelden"
						})
					]
				}),
				/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Link, {
					to: "/",
					className: "mt-4 inline-flex h-11 items-center text-sm text-muted hover:text-fg",
					children: "Zurück zur Startseite"
				})
			]
		})
	});
}
var fieldClass = "h-11 w-full rounded-md bg-elevated px-3 text-sm text-fg outline-none ring-accent/60 placeholder:text-subtle focus-visible:ring-2";
function Field({ label, children }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)("label", {
		className: "block",
		children: [/* @__PURE__ */ (0, import_jsx_runtime.jsx)("span", {
			className: "mb-1.5 block text-xs font-medium uppercase tracking-widest text-muted",
			children: label
		}), children]
	});
}
function ModeTab({ active, onClick, children }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)("button", {
		type: "button",
		onClick,
		className: active ? "h-10 flex-1 rounded-sm bg-surface text-sm text-fg" : "h-10 flex-1 rounded-sm text-sm text-muted hover:text-fg",
		children
	});
}
//#endregion
export { Login as component };
