// Gemeinsamer Kern von Nori für alle JavaScript-Clients.
//
// Die Apple-Apps teilen ihren Kern unter `native/NoriCore/`; dies ist dessen
// Entsprechung für TypeScript. Beide Seiten richten sich nach demselben
// Vertrag — `config/contract.json`.

export * from "./models.js";
export * from "./rules.js";
export * from "./http.js";
export * from "./dom.js";
export * from "./client.js";
export * from "./library.js";
export * from "./sync.js";
export * from "./sync-engine.js";
export * from "./google/drive.js";
export * from "./google/auth.js";
export * from "./gateway.js";
export * from "./hoster/safety.js";
export * from "./hoster/sites.js";
export * from "./hoster/resolver.js";
export * from "./hoster/voe.js";
// Eigener Namensraum: `normalize` heißt im Parser wie in der
// TMDB-Zuordnung, meint aber etwas anderes.
export * as aniworld from "./parse/aniworld.js";
export * as serienstream from "./parse/serienstream.js";
export * from "./parse/common.js";
export * from "./tmdb/index.js";
