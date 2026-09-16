/** Die Version aus `appinfo.json`, beim Bauen eingesetzt (`vite.config.ts`). */
declare const __NORI_WEBOS_VERSION__: string;

/**
 * Die Zeichenfläche aus `appinfo.json` (`resolution`), etwa `"1920x1080"`.
 *
 * Auf webOS ist das die Fläche, in der die App tatsächlich zeichnet — auch auf
 * einem 4K-Panel. `services/images.ts` begrenzt daran die angeforderten
 * Bildgrößen.
 */
declare const __NORI_WEBOS_RESOLUTION__: string;
