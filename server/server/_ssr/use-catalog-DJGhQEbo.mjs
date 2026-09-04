import { o as __toESM } from "../_runtime.mjs";
import { n as require_react } from "../_libs/@radix-ui/react-compose-refs+[...].mjs";
import { r as useQueryClient, t as useQuery } from "../_libs/react+tanstack__react-query.mjs";
import { a as otherProvider, s as useProvider } from "./provider-B-pxa-h2.mjs";
import { h as readCachedCatalog } from "./router-DDQw7P_P.mjs";
import { r as fetchCatalog } from "./cover-prefetch-Dz9cGrY_.mjs";
//#region node_modules/.nitro/vite/services/ssr/assets/use-catalog-DJGhQEbo.js
var import_react = /* @__PURE__ */ __toESM(require_react());
function useCatalog() {
	const qc = useQueryClient();
	const provider = useProvider((s) => s.provider);
	const query = useQuery({
		queryKey: ["catalog", provider],
		queryFn: () => fetchCatalog({ data: { provider } }),
		placeholderData: () => readCachedCatalog(provider),
		staleTime: 6e5,
		gcTime: 36e5,
		retry: 0,
		refetchOnWindowFocus: false
	});
	(0, import_react.useEffect)(() => {
		if (provider !== "aniworld") return;
		if (qc.getQueryData(["catalog", provider])?.items?.length) return;
		let cancelled = false;
		import("./client-fallback-BxiYvHD-.mjs").then(({ fallbackCatalog }) => {
			if (cancelled) return;
			if (qc.getQueryData(["catalog", provider])?.items?.length) return;
			qc.setQueryData(["catalog", provider], fallbackCatalog());
		});
		return () => {
			cancelled = true;
		};
	}, [qc, provider]);
	(0, import_react.useEffect)(() => {
		const other = otherProvider(provider);
		if (qc.getQueryData(["catalog", other])) return;
		const cached = readCachedCatalog(other);
		if (cached.items.length) {
			qc.setQueryData(["catalog", other], cached);
			return;
		}
		qc.prefetchQuery({
			queryKey: ["catalog", other],
			queryFn: () => fetchCatalog({ data: { provider: other } }),
			staleTime: 6e5
		});
	}, [
		qc,
		provider,
		query.data
	]);
	return query;
}
//#endregion
export { useCatalog as t };
