import { n as create, t as persist } from "../_libs/zustand.mjs";
import { a as APP_VERSION, s as compareVersions } from "./router-DDQw7P_P.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/updates-DUQY2QP2.js
var useUpdates = create()(persist((set) => ({
	autoCheck: true,
	lastChecked: null,
	downloadedVersion: null,
	remote: null,
	checking: false,
	error: null,
	setAutoCheck: (autoCheck) => set({ autoCheck }),
	markDownloaded: (version) => set({ downloadedVersion: version }),
	checkNow: async () => {
		set({
			checking: true,
			error: null
		});
		try {
			const res = await fetch("/api/nori-update", { cache: "no-store" });
			if (!res.ok) throw new Error("Update-Info nicht erreichbar");
			const remote = await res.json();
			set({
				remote,
				lastChecked: Date.now(),
				checking: false
			});
			return remote;
		} catch (err) {
			set({
				checking: false,
				error: err instanceof Error ? err.message : "Prüfung fehlgeschlagen"
			});
			return null;
		}
	}
}), {
	name: "nori-updates",
	version: 2,
	migrate: (persisted) => {
		const prev = persisted ?? {};
		return {
			autoCheck: prev.autoCheck ?? true,
			lastChecked: null,
			downloadedVersion: prev.downloadedVersion ?? null
		};
	},
	partialize: (s) => ({
		autoCheck: s.autoCheck,
		lastChecked: s.lastChecked,
		downloadedVersion: s.downloadedVersion
	})
}));
function portableIsNewer(remote, downloadedVersion) {
	if (!remote?.portable.available) return false;
	const latest = remote.portable.version ?? remote.version;
	if (!downloadedVersion) return compareVersions(latest, APP_VERSION) >= 0;
	return compareVersions(latest, downloadedVersion) > 0;
}
//#endregion
export { useUpdates as n, portableIsNewer as t };
