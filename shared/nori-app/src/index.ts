// Die gemeinsame Anwendungsschicht der Nori-Clients.
//
// ## Was hier liegt und was nicht
//
// Nori hat drei Ebenen, und die Trennung ist keine Geschmacksfrage:
//
//     @nori/core   Quellen, Modelle, Regeln, Hoster, TMDB-Client, Drive,
//                  Merge-Regeln. Kennt keine Oberfläche, läuft auch in Node.
//
//     @nori/app    Diese Ebene. Was jede Nori-Oberfläche braucht, um aus dem
//                  Kern eine App zu machen: Bildindex, TMDB-Zwischenspeicher,
//                  Bibliothekszustand, Katalogansicht, Startseitenrangfolge,
//                  Geräteeinstellungen, Bildwarteschlange, Leistungsmodus.
//                  Kennt React, aber kein einziges Element — hier wird nichts
//                  gezeichnet.
//
//     apps/*       Die Oberflächen. Der Fernseher mit seiner
//                  Fernbedienungsnavigation, der Desktop mit Maus und
//                  Tastatur. Sie sehen unterschiedlich aus, weil sie
//                  unterschiedlich bedient werden — und teilen sich alles
//                  darunter.
//
// Was an dieser Ebene plattformabhängig ist, steht in `platform.ts` und wird
// von der App beim Start angemeldet. Vier Fragen, mehr nicht.

export * from "./platform";

export * from "./services/log";
export * from "./services/gateway";
export * from "./services/tmdb";
export * from "./services/tmdbStatus";
export * from "./services/covers";
export * from "./services/images";
export * from "./services/performance";
export * from "./services/scheduler";
export * from "./services/artworkQueue";

export * from "./state/data";
export * from "./state/library";
export * from "./state/settings";
export * from "./state/catalog";
export * from "./state/catalogOrder";
export * from "./state/home";
export * from "./state/calendarDates";

export * from "./hooks/useAsync";
export * from "./hooks/useDebounced";
export * from "./hooks/usePersistentState";
export * from "./hooks/useTick";

export * from "./player/hlsLoader";
export * from "./player/hlsPlayback";

export * from "./ui/Artwork";
export * from "./ui/Icon";

export * from "./meta";
