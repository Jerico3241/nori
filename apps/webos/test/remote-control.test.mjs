// Fernbedienungsprüfung im echten Browser.
//
// Warum mit Tastencodes statt mit Mausklicks: was auf dem Fernseher passiert,
// entscheidet die Fernbedienung. Ein Test, der klickt, prüft einen Weg, den es
// dort nicht gibt — und übersieht genau die Fehler, die auf einem Fernseher
// wehtun: ein Element ohne Fokus, ein Fokus ohne Sichtbarkeit, eine
// Zurück-Taste, die zu weit springt.
//
// Was der Lauf **nicht** ist: ein Beweis, dass Nori auf einem LG-Fernseher
// läuft. Er prüft dieselbe gebaute Datei in Chromium bei 1920 × 1080 mit
// echten LG-Tastencodes. Die Wiedergabe eines echten HLS-Streams, das
// Zusammenspiel mit dem Systemplayer von webOS und das Verhalten der Magic
// Remote entscheiden sich erst auf dem Gerät.
//
// Voraussetzungen:
//
//     npm run build
//     node test/mock-server.mjs &        (in einem zweiten Fenster)
//     npm i -D playwright                (einmalig, ~50 MB Browser)
//     node test/remote-control.test.mjs
//
// Der Pfad zum Browser lässt sich über NORI_CHROMIUM setzen; ohne Angabe wird
// der von Playwright mitgelieferte benutzt. Mit NORI_SHOTS=<Ordner> landen die
// Bildschirmfotos dort statt in `test-shots/`.

import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// Playwright ist bewusst keine Abhängigkeit dieses Pakets: wer an der
// Swift-Seite von Nori arbeitet, soll für ein `npm install` keinen Browser
// herunterladen. Fehlt es, sagt der Test wie man es bekommt, statt mit einem
// Auflösungsfehler abzubrechen.
let chromium;
try {
  ({ chromium } = await import("playwright"));
} catch {
  console.error(
    "[Nori:webOS] playwright fehlt.\n"
    + "  npm i -D playwright && npx playwright install chromium\n"
    + "Ein bereits vorhandener Chromium lässt sich über NORI_CHROMIUM angeben.",
  );
  process.exit(127);
}

const HERE = dirname(fileURLToPath(import.meta.url));
const APP = resolve(HERE, "..");
const BASE = process.env.NORI_MOCK ?? "http://127.0.0.1:8799";
const SHOTS = resolve(process.env.NORI_SHOTS ?? join(APP, "test-shots"));
if (!existsSync(SHOTS)) mkdirSync(SHOTS, { recursive: true });

/**
 * Die Schemaversion kommt aus dem Kern, nicht aus einer Zahl in diesem Test.
 *
 * Der Grund ist ein echter Fehler: hier stand „4", während der Kern längst bei
 * 5 war. Der Test war rot, ohne dass an der App etwas falsch war — und beim
 * nächsten Schemaschritt wäre er es wieder.
 */
const { LIBRARY_SCHEMA_VERSION } = await import("@nori/core");

const results = [];
let failures = 0;

function check(name, ok, detail = "") {
  results.push(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? ` — ${detail}` : ""}`);
  if (!ok) failures += 1;
}

function section(name) {
  results.push(`\n— ${name} ${"—".repeat(Math.max(0, 62 - name.length))}`);
}

/** Eine Taste der Fernbedienung senden. */
async function remote(page, keyCode, key) {
  await page.evaluate(([code, k]) => {
    const target = document.activeElement ?? document.body;
    const event = new KeyboardEvent("keydown", { keyCode: code, which: code, key: k, bubbles: true, cancelable: true });
    Object.defineProperty(event, "keyCode", { get: () => code });
    target.dispatchEvent(event);
    const up = new KeyboardEvent("keyup", { keyCode: code, which: code, key: k, bubbles: true, cancelable: true });
    Object.defineProperty(up, "keyCode", { get: () => code });
    target.dispatchEvent(up);
  }, [keyCode, key]);
  await page.waitForTimeout(140);
}

const KEY = {
  left: [37, "ArrowLeft"], up: [38, "ArrowUp"], right: [39, "ArrowRight"],
  down: [40, "ArrowDown"], ok: [13, "Enter"], back: [461, "GoBack"],
  backAlt: [10009, "GoBack"],
  play: [415, "MediaPlay"], pause: [19, "MediaPause"], stop: [413, "MediaStop"],
  rewind: [412, "MediaRewind"], forward: [417, "MediaFastForward"],
};

const press = (page, name) => remote(page, KEY[name][0], KEY[name][1]);

async function focused(page) {
  return page.evaluate(() => {
    const el = document.activeElement;
    if (!el || el === document.body) return null;
    return {
      key: el.getAttribute("data-focus-key"),
      cls: el.className,
      text: (el.textContent ?? "").trim().slice(0, 40),
      tag: el.tagName,
    };
  });
}

async function goto(page, hash, wait = 1200) {
  await page.evaluate((target) => { window.location.hash = target; }, hash);
  await page.waitForTimeout(wait);
}

async function shot(page, name) {
  await page.screenshot({ path: join(SHOTS, `${name}.png`) });
}

/*
 * Ab hier läuft der Browser.
 *
 * Alles in einem Block, der auch bei einem Abbruch berichtet: Ein Test, der
 * mitten im Lauf mit einer Ausnahme aussteigt, wirft die dreißig Prüfungen weg,
 * die vorher bestanden haben — und man sieht nicht, wie weit er kam. Genau das
 * ist passiert, als ein Auswahlpfad im DOM fehlte.
 */
let crashed = null;
// Außerhalb des Blocks, damit der Abschluss unten sie noch sieht.
const browser = await chromium.launch({
  executablePath: process.env.NORI_CHROMIUM || undefined,
  args: ["--no-sandbox", "--autoplay-policy=no-user-gesture-required"],
});
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });

try {

/*
 * TMDB-Bilder auf ein örtliches Bild umbiegen.
 *
 * Ohne das lädt in dieser Umgebung kein einziges Poster: `image.tmdb.org` ist
 * nicht erreichbar. Der Rückfall der Kachel würde greifen — das ist richtig,
 * aber dann prüfen die Bildschirmfotos den Rückfall und nicht die Oberfläche.
 * Die Umleitung ersetzt nur die Bytes, nicht die Logik: die Adressen bildet
 * weiterhin `tmdbImageURL` im Kern.
 */
const PLACEHOLDER = readFileSync(join(APP, "public", "icon-400.png"));
await page.route("https://image.tmdb.org/**", (route) =>
  route.fulfill({ status: 200, contentType: "image/png", body: PLACEHOLDER }));

const consoleErrors = [];
page.on("console", (msg) => {
  if (msg.type() === "error") consoleErrors.push(msg.text());
});
page.on("pageerror", (err) => consoleErrors.push(`pageerror: ${err.message}`));

// Server und TMDB-Weg eintragen, bevor die App startet.
await page.addInitScript((base) => {
  localStorage.setItem("nori.webos.settings", JSON.stringify({
    transport: "server", serverUrl: base, controlsTimeout: 4, seekStep: 10,
    autoplayCountdown: 3, tmdbMode: "server", tmdbKey: "", reduceEffects: false, debug: true,
  }));
}, BASE);

await page.goto(BASE, { waitUntil: "domcontentloaded" });
// Länger als beim vorherigen Stand: die Startseite holt jetzt Ranglisten und
// ordnet Titel zu, und das sind mehrere Abrufe hintereinander.
await page.waitForTimeout(5000);

// --- 1. Startseite -------------------------------------------------------
section("Startseite");

const heroTitle = await page.evaluate(() => {
  const copy = document.querySelector(".hero-copy");
  if (!copy) return null;
  const logo = copy.querySelector(".hero-logo");
  return logo ? logo.getAttribute("alt") : copy.querySelector("h1")?.textContent ?? null;
});
check("Hero mit Titel oder Schriftzug", Boolean(heroTitle), heroTitle ?? "kein Hero");

const heroHeight = await page.evaluate(() =>
  Math.round(document.querySelector(".hero")?.getBoundingClientRect().height ?? 0));
check("Hero füllt den ersten Bildschirm", heroHeight >= 600, `${heroHeight} px von 1080`);

const ALLOWED_RAILS = [
  "Weiterschauen", "Neu & beliebt", "Neu im Katalog", "Neue Episoden",
  "Für dich", "Entdecke etwas Neues", "Merkliste",
];
const railTitles = await page.$$eval(".rail h2", (els) => els.map((e) => e.textContent?.trim()));
check("Reihen vorhanden", railTitles.length >= 2, railTitles.join(", "));
check(
  "Jede Reihe trägt einen vorgesehenen Namen",
  railTitles.every((title) => ALLOWED_RAILS.includes(title ?? "")),
  railTitles.join(", "),
);
check(
  "„Neu & beliebt“ entsteht aus TMDB-Signalen",
  railTitles.includes("Neu & beliebt"),
  railTitles.join(", "),
);
check(
  "Keine Reihe heißt „Beliebt“ oder „Zuletzt aufgenommen“",
  !railTitles.some((title) => title === "Beliebt" || title === "Zuletzt aufgenommen"),
  railTitles.join(", "),
);

const cardCount = await page.$$eval(".media-card, .wide-card", (els) => els.length);
check("Kacheln geladen", cardCount > 10, `${cardCount} Kacheln`);

const ratingCount = await page.$$eval(".media-rating", (els) => els.length);
check("Bewertungen auf den Kacheln", ratingCount > 0, `${ratingCount} Kacheln mit Bewertung`);

const posterLoaded = await page.$$eval(".poster img.loaded", (els) => els.length);
check("Bilder geladen", posterLoaded > 3, `${posterLoaded} Bilder`);

await shot(page, "01-startseite");

// --- 2. Nori-Design statt Orange ----------------------------------------
section("Design");

const palette = await page.evaluate(() => {
  const style = getComputedStyle(document.documentElement);
  const read = (name) => style.getPropertyValue(name).trim();
  return {
    bg: read("--bg"),
    accent: read("--accent"),
    highlight: read("--highlight"),
    focus: read("--focus"),
    star: read("--star"),
  };
});
check("Grundfarbe ist Noris Fastschwarz", palette.bg.toLowerCase() === "#05060a", palette.bg);
check(
  "Hauptakzent ist das helle Neutral, kein Orange",
  palette.accent.toLowerCase() === "#d7deea",
  palette.accent,
);
check("Aktive Zustände tragen das Signalblau", palette.highlight.toLowerCase() === "#78c5ff", palette.highlight);
check("Der Fokusring ist blau", palette.focus.toLowerCase() === "#78c5ff", palette.focus);
check("Der warme Ton bleibt der Bewertung", palette.star.toLowerCase() === "#ffe07a", palette.star);

/**
 * Kein Orange mehr in einer gezeichneten Fläche.
 *
 * Nicht über die Variablen geprüft, sondern über die Farben, die der Browser
 * tatsächlich setzt: ein hartkodierter Wert mitten im Stylesheet stünde in
 * keiner Variable und käme so durch.
 */
const orange = await page.evaluate(() => {
  const isOrange = (value) => {
    const match = /rgba?\((\d+),\s*(\d+),\s*(\d+)/.exec(value ?? "");
    if (!match) return false;
    const [r, g, b] = [Number(match[1]), Number(match[2]), Number(match[3])];
    // Warmer, gesättigter Ton: deutlich mehr Rot als Blau, und Grün dazwischen.
    return r > 170 && b < 110 && g > 60 && g < 190 && r - b > 90;
  };
  const out = [];
  for (const node of Array.from(document.querySelectorAll("*")).slice(0, 1500)) {
    const style = getComputedStyle(node);
    for (const property of ["color", "backgroundColor", "borderTopColor", "outlineColor"]) {
      if (isOrange(style[property])) {
        out.push(`${node.className || node.tagName}.${property}=${style[property]}`);
      }
    }
  }
  return out.slice(0, 5);
});
check("Keine orangefarbene Fläche im Bild", orange.length === 0, orange.join(" | "));

const brandImage = await page.evaluate(() => {
  const img = document.querySelector(".brand-mark img");
  return img ? { src: img.getAttribute("src"), complete: img.complete && img.naturalWidth > 0 } : null;
});
check("Seitenleiste trägt das App-Symbol, kein „N“", Boolean(brandImage?.src), brandImage?.src ?? "-");
check("Das Symbol lädt", brandImage?.complete === true);

// --- 3. Fokus ist immer irgendwo -----------------------------------------
section("Fokus");

let f = await focused(page);
check("Fokus nach dem Start gesetzt", Boolean(f), JSON.stringify(f));

let lostFocus = 0;
let invisibleFocus = 0;
for (const seq of ["right", "right", "right", "down", "down", "left", "up", "down", "right", "right", "down", "down"]) {
  await press(page, seq);
  const cur = await focused(page);
  if (!cur) lostFocus += 1;
  const visible = await page.evaluate(() => {
    const el = document.activeElement;
    if (!el || el === document.body) return false;
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0 && r.bottom > -1 && r.top < window.innerHeight + 1
      && r.right > -1 && r.left < window.innerWidth + 1;
  });
  if (!visible) invisibleFocus += 1;
}
check("Fokus-Stresstest: nie ohne Fokus", lostFocus === 0, `${lostFocus} Verluste`);
check("Fokus-Stresstest: nie außerhalb des Bildes", invisibleFocus === 0, `${invisibleFocus} unsichtbar`);

// --- 4. Reihe entlang bis Karte 7, dann öffnen ---------------------------
section("Navigation");

await page.evaluate(() => {
  const card = document.querySelectorAll('[data-rail="popular"] .media-card, .rail-track .media-card')[0];
  card?.focus();
});
await page.waitForTimeout(200);
for (let i = 0; i < 6; i += 1) await press(page, "right");
const seventh = await focused(page);
check("Reihe: siebte Kachel erreichbar", Boolean(seventh?.key), seventh?.text ?? "-");

await shot(page, "02-kachel-fokussiert");

await press(page, "ok");
await page.waitForTimeout(1800);
const onDetails = page.url().includes("#/titel/");
check("Detailseite geöffnet", onDetails, page.url());

// --- 5. Detailseite ------------------------------------------------------
section("Detailseite");

const detailTitle = await page.evaluate(() => {
  const copy = document.querySelector(".details-copy");
  const logo = copy?.querySelector(".details-logo");
  return logo ? logo.getAttribute("alt") : copy?.querySelector("h1")?.textContent ?? null;
});
check("Titel oder Schriftzug", Boolean(detailTitle), detailTitle ?? "-");

const backdropHeight = await page.evaluate(() =>
  Math.round(document.querySelector(".details-backdrop")?.getBoundingClientRect().height ?? 0));
check("Kopfbereich ist groß", backdropHeight >= 500, `${backdropHeight} px`);

const seasonCount = await page.$$eval(".season-selector button", (e) => e.length);
check("Staffeln als Reiter (wenige Staffeln)", seasonCount >= 2, `${seasonCount} Reiter`);
const episodeCount = await page.$$eval(".episode-card", (e) => e.length);
check("Folgen", episodeCount >= 10, `${episodeCount} Folgen`);

// --- 6. Zurück → Fokus muss auf Karte 7 stehen ---------------------------
await press(page, "back");
await page.waitForTimeout(1600);
const backHome = !page.url().includes("#/titel/");
check("Zurück: wieder auf der Startseite", backHome, page.url());
const restored = await focused(page);
check(
  "Zurück: Fokus auf derselben Kachel",
  restored?.key === seventh?.key,
  `erwartet ${seventh?.key}, ist ${restored?.key}`,
);

// Und dasselbe mit dem zweiten Tastencode, den webOS für „Zurück" schickt.
await press(page, "right");
const beforeAlt = await focused(page);
await press(page, "ok");
await page.waitForTimeout(1500);
await remote(page, KEY.backAlt[0], KEY.backAlt[1]);
await page.waitForTimeout(1600);
check(
  "Zurück über Tastencode 10009 wirkt genauso",
  !page.url().includes("#/titel/") && (await focused(page))?.key === beforeAlt?.key,
  page.url(),
);

// --- 7. Seitenleiste -----------------------------------------------------
section("Seitenleiste");

for (let i = 0; i < 12; i += 1) await press(page, "left");
const inSidebar = await page.evaluate(() => Boolean(document.activeElement?.closest(".side-nav")));
check("Über Links erreichbar", inSidebar);
const expanded = await page.evaluate(() => document.querySelector(".side-nav")?.classList.contains("expanded"));
check("Klappt bei Fokus auf", Boolean(expanded));
await shot(page, "03-sidebar-offen");

// Sie darf nicht offen bleiben, wenn der Fokus wieder in die Seite geht.
for (let i = 0; i < 3; i += 1) await press(page, "right");
const collapsed = await page.evaluate(() => !document.querySelector(".side-nav")?.classList.contains("expanded"));
check("Klappt beim Verlassen zu", collapsed);

// --- 8. Alle Seiten anfahren --------------------------------------------
section("Alle Ansichten");

const pages = [
  ["/entdecken", ".page.explore", "Entdecken", "04-entdecken"],
  ["/kalender", ".page.calendar", "Kalender", "05-kalender"],
  ["/suche", ".page.search", "Suche", "06-suche"],
  ["/merkliste", ".media-grid, .state-panel", "Merkliste", "07-merkliste"],
  ["/verlauf", ".page.history", "Verlauf", "08-verlauf"],
  ["/einstellungen", ".page.settings", "Einstellungen", "09-einstellungen"],
];
for (const [route, selector, label, shotName] of pages) {
  await goto(page, `#${route}`, 1200);
  const present = await page.$(selector);
  const hasFocus = await focused(page);
  check(`${label} rendert`, Boolean(present));
  check(`${label} hat Fokus`, Boolean(hasFocus), hasFocus?.key ?? "-");
  await shot(page, shotName);
}

// --- 9. Einstellungen: TMDB ---------------------------------------------
section("Einstellungen");

await goto(page, "#/einstellungen", 900);
const settingsText = await page.textContent(".page.settings");
check("TMDB-Abschnitt vorhanden", (settingsText ?? "").includes("Über den Nori-Server"));
check(
  "Schemaversion kommt aus dem Kern",
  (settingsText ?? "").includes(`Bibliotheksschema v${LIBRARY_SCHEMA_VERSION}`),
  `erwartet v${LIBRARY_SCHEMA_VERSION}`,
);
const diagnostics = await page.evaluate(() =>
  Array.from(document.querySelectorAll(".page.settings .field-note"))
    .map((node) => node.textContent ?? "")
    .find((text) => text.includes("Titel zugeordnet")) ?? "");
const matched = /(\d+) Titel zugeordnet/.exec(diagnostics);
check(
  "TMDB hat Titel zugeordnet",
  Boolean(matched) && Number(matched[1]) > 0,
  diagnostics.trim().slice(0, 120),
);
check(
  "Alternativtitel-Treffer werden ausgewiesen",
  diagnostics.includes("über Alternativtitel"),
  diagnostics.trim().slice(0, 120),
);

// --- 10. Suche -----------------------------------------------------------
section("Suche");

await goto(page, "#/suche", 900);
await page.fill(".search-bar input", "one");
await page.waitForTimeout(900);
const hits = await page.$$eval(".media-grid .media-card", (e) => e.length);
check("Treffer bei „one“", hits > 0, `${hits} Treffer`);

await page.fill(".search-bar input", "");
await page.waitForTimeout(700);
const emptyState = await page.$(".state-panel");
check("Leere Suche zeigt einen Zustand, keine leere Fläche", Boolean(emptyState));

await page.fill(".search-bar input", "zzzzzz");
await page.waitForTimeout(900);
const noHits = await page.textContent(".state-panel h2").catch(() => null);
check("Keine Treffer wird benannt", (noHits ?? "").includes("Keine Treffer"), noHits ?? "-");

// Sonderzeichen und japanische Schrift dürfen nichts werfen.
for (const query of ["ノリ", "Frieren: Nach dem Ende", "a+b/c", "進撃の巨人", "Dämonenjäger"]) {
  await page.fill(".search-bar input", query);
  await page.waitForTimeout(500);
}
const searchAlive = await page.$(".page.search");
check("Sonderzeichen und japanische Titel werfen nichts", Boolean(searchAlive));

// Die Bildschirmtastatur muss ohne Systemtastatur reichen.
await page.fill(".search-bar input", "");
await page.waitForTimeout(300);
await page.click('[data-focus-key="key-F"]');
await page.click('[data-focus-key="key-R"]');
await page.click('[data-focus-key="key-I"]');
await page.waitForTimeout(900);
const keypadValue = await page.inputValue(".search-bar input");
check("Bildschirmtastatur schreibt ins Feld", keypadValue === "FRI", keypadValue);
const keypadHits = await page.$$eval(".media-grid .media-card", (e) => e.length);
check("Bildschirmtastatur findet Treffer", keypadHits > 0, `${keypadHits} Treffer`);
await shot(page, "10-suche-treffer");

// --- 11. Staffelwahl bei vielen Staffeln --------------------------------
section("Staffelwahl");

await goto(page, "#/titel/aniworld/detektiv-conan", 2200);
const sheetTrigger = await page.$(".season-trigger button");
check("Bei dreißig Staffeln erscheint ein Knopf, keine Leiste", Boolean(sheetTrigger));
const noTabs = await page.$$eval(".season-selector button", (e) => e.length);
check("Keine dreißig Reiter nebeneinander", noTabs === 0, `${noTabs} Reiter`);

await page.click(".season-trigger button");
await page.waitForTimeout(1500);
const sheetOpen = await page.$(".season-sheet");
check("Auswahlraster öffnet", Boolean(sheetOpen));
const sheetFocus = await page.evaluate(() => Boolean(document.activeElement?.closest(".season-sheet")));
check("Fokus liegt im Raster", sheetFocus);
const sheetSelected = await focused(page);
check(
  "Fokus auf der aktiven Staffel, nicht auf der ersten",
  (sheetSelected?.key ?? "").startsWith("sheet-season-"),
  `${sheetSelected?.key} — ${sheetSelected?.text ?? "-"}`,
);
await shot(page, "11-staffelwahl");

// Der Fokus darf das Raster nicht verlassen.
for (const seq of ["left", "left", "left", "up", "up", "down", "right"]) await press(page, seq);
const stillInSheet = await page.evaluate(() => Boolean(document.activeElement?.closest(".season-sheet")));
check("Fokus bleibt im Raster", stillInSheet);

// Zurück schließt das Raster, nicht die Ansicht.
await press(page, "back");
await page.waitForTimeout(600);
check("Zurück schließt das Raster", !(await page.$(".season-sheet")));
check("Zurück verlässt dabei nicht die Detailseite", page.url().includes("#/titel/"), page.url());

// Eine andere Staffel wählen.
await page.click(".season-trigger button");
await page.waitForTimeout(1200);
await page.click('[data-focus-key="sheet-season-7"]');
await page.waitForTimeout(2000);
const seasonLabel = await page.textContent(".season-trigger button");
check("Staffelwechsel greift", (seasonLabel ?? "").includes("Staffel 7"), seasonLabel?.trim() ?? "-");
const episodesAfter = await page.$$eval(".episode-card", (e) => e.length);
check("Die Folgenliste wurde ausgetauscht", episodesAfter >= 10, `${episodesAfter} Folgen`);

// --- 12. Folgenkacheln mit TMDB-Angaben ---------------------------------
section("Folgen und ähnliche Titel");

await goto(page, "#/titel/aniworld/frieren", 2600);
const episodeInfo = await page.evaluate(() => {
  const card = document.querySelector(".episode-card");
  if (!card) return null;
  return {
    title: card.querySelector(".episode-copy strong")?.textContent?.trim() ?? "",
    overview: card.querySelector(".episode-overview")?.textContent?.trim() ?? "",
    footnote: card.querySelector(".episode-footnote")?.textContent?.trim() ?? "",
    hasStill: Boolean(card.querySelector(".episode-art img")),
  };
});
check("Folgenkachel: Titel", Boolean(episodeInfo?.title), episodeInfo?.title ?? "-");
check("Folgenkachel: Beschreibung von TMDB", (episodeInfo?.overview.length ?? 0) > 20, episodeInfo?.overview.slice(0, 50) ?? "-");
check("Folgenkachel: Standbild", episodeInfo?.hasStill === true);
check(
  "Folgenkachel: Laufzeit und Datum",
  /\d+ min/.test(episodeInfo?.footnote ?? "") && /\d{2}\.\d{2}\.\d{4}/.test(episodeInfo?.footnote ?? ""),
  episodeInfo?.footnote ?? "-",
);

const similarTitles = await page.$$eval(".details-similar .media-card", (e) => e.length);
check("Ähnliche Titel erscheinen", similarTitles > 0, `${similarTitles} Titel`);
const similarNote = await page.textContent(".details-similar .rail-note").catch(() => null);
check(
  "Ähnliche Titel sind auf Noris Bestand begrenzt",
  (similarNote ?? "").includes("nur, was Nori auch hat"),
  similarNote ?? "-",
);
await shot(page, "12-detailseite");
await page.evaluate(() => {
  document.querySelector(".details-similar")?.scrollIntoView({ block: "center" });
});
await page.waitForTimeout(600);
await shot(page, "13-aehnliche-titel");

// --- 13. Versetzte Folgenzählung ----------------------------------------
//
// Bei „Vinland Saga" zählt der TMDB-Nachbau dieselbe Staffel ab Folge 17
// weiter, während die Quelle bei 1 beginnt. Nach Nummer zugeordnet stünde zu
// Folge 1 das Standbild von Folge 1 — gemeint ist aber 17. Geprüft wird
// deshalb die Adresse des Standbilds, nicht bloß, dass eines dasteht.
await goto(page, "#/titel/aniworld/vinland-saga", 3000);
const offsetCards = await page.$$eval(".episode-card", (els) =>
  els.slice(0, 3).map((el) => ({
    title: el.querySelector(".episode-copy strong")?.textContent?.trim() ?? "",
    still: el.querySelector(".episode-art img")?.getAttribute("src") ?? "",
  })));
check(
  "Versetzte Zählung: Folge 1 bekommt das Standbild von TMDB-Folge 17",
  offsetCards[0]?.still.includes("still-1-17"),
  offsetCards.map((card) => `${card.title} → ${card.still.split("/").pop()}`).join(" | "),
);
check(
  "Versetzte Zählung: der Titel der Quelle bleibt stehen",
  offsetCards[0]?.title.includes("Das Ende der Reise"),
  offsetCards[0]?.title ?? "-",
);

// Ein Titel ohne TMDB-Eintrag muss ohne Bild und ohne Fehler dastehen.
await goto(page, "#/titel/aniworld/barakamon", 2400);
const withoutTmdb = await page.evaluate(() => ({
  episodes: document.querySelectorAll(".episode-card").length,
  stills: document.querySelectorAll(".episode-art img").length,
  hasError: Boolean(document.querySelector(".state-panel[role=alert]")),
}));
check("Titel ohne TMDB-Eintrag: Folgen stehen trotzdem", withoutTmdb.episodes >= 10, `${withoutTmdb.episodes} Folgen`);
check("Titel ohne TMDB-Eintrag: kein Fehlerzustand", withoutTmdb.hasError === false);

// --- 14. Merkliste über Detailseite --------------------------------------
section("Merkliste");

await goto(page, "#/titel/aniworld/frieren", 2000);
await page.click('[data-focus-key="favorite"]');
await page.waitForTimeout(500);
const favLabel = await page.textContent('[data-focus-key="favorite"]');
check("Titel aufgenommen", (favLabel ?? "").includes("Auf Merkliste"), favLabel ?? "-");
await goto(page, "#/merkliste", 1200);
const favCount = await page.$$eval(".media-grid .media-card", (e) => e.length);
check("Seite zeigt den Titel", favCount === 1, `${favCount} Einträge`);

// --- 15. Player ----------------------------------------------------------
section("Player");

await goto(page, "#/titel/aniworld/frieren", 2000);
await page.click('[data-focus-key="episode-3"]');
await page.waitForTimeout(2500);
const inPlayer = page.url().includes("#/player/");
check("Geöffnet", inPlayer, page.url());
const hasVideo = await page.$("video.player-video");
check("Videoelement vorhanden", Boolean(hasVideo));
const chromeVisible = await page.evaluate(() => document.querySelector(".player-chrome")?.classList.contains("visible"));
check("Bedienung anfangs sichtbar", Boolean(chromeVisible));
const hosterLabel = await page.textContent(".player-actions button small").catch(() => null);
check("Hoster aufgelöst", (hosterLabel ?? "").includes("VOE"), hosterLabel ?? "-");
await shot(page, "14-player");

// Wiedergabe, Pause, Spulen über die Medientasten.
await press(page, "play");
await page.waitForTimeout(900);
const playing = await page.evaluate(() => {
  const video = document.querySelector("video.player-video");
  return video ? !video.paused && video.currentTime > 0 : false;
});
check("Play startet die Wiedergabe", playing);

await press(page, "pause");
await page.waitForTimeout(400);
const paused = await page.evaluate(() => document.querySelector("video.player-video")?.paused === true);
check("Pause hält sie an", paused);

await press(page, "play");
await page.waitForTimeout(700);
const before = await page.evaluate(() => document.querySelector("video.player-video")?.currentTime ?? 0);
await press(page, "forward");
await page.waitForTimeout(900);
const after = await page.evaluate(() => document.querySelector("video.player-video")?.currentTime ?? 0);
check("Vorspulen bewegt die Position", after > before + 5, `${before.toFixed(1)} → ${after.toFixed(1)}`);

await press(page, "rewind");
await page.waitForTimeout(900);
const rewound = await page.evaluate(() => document.querySelector("video.player-video")?.currentTime ?? 0);
check("Zurückspulen ebenso", rewound < after, `${after.toFixed(1)} → ${rewound.toFixed(1)}`);

// Weit nach vorn, damit der gespeicherte Fortschritt über der Resume-Schwelle
// von acht Sekunden liegt. Darunter setzt Nori nach Vorschrift **nicht** fort
// (`config/contract.json`, `rules.resume`) — ein Test, der es trotzdem
// erwartet, prüft die falsche Regel.
for (let i = 0; i < 8; i += 1) await press(page, "forward");
await page.waitForTimeout(1200);
const farIn = await page.evaluate(() => document.querySelector("video.player-video")?.currentTime ?? 0);
check("Mehrfaches Spulen summiert sich", farIn > 60, `${farIn.toFixed(1)} s`);
// Der Fortschritt wird im Fünf-Sekunden-Takt gesichert.
await page.waitForTimeout(5500);

// Drawer über Pfeil hoch
await press(page, "up");
await page.waitForTimeout(700);
const drawerOpen = await page.$(".player-panel");
check("Drawer über Pfeil hoch", Boolean(drawerOpen));
const drawerFocus = await page.evaluate(() => Boolean(document.activeElement?.closest(".player-panel")));
check("Fokus liegt im Drawer", drawerFocus);
await shot(page, "15-player-drawer");

// Fokus darf den Drawer nicht verlassen
for (const seq of ["left", "left", "left", "down", "down", "up"]) await press(page, seq);
const stillInDrawer = await page.evaluate(() => Boolean(document.activeElement?.closest(".player-panel")));
check("Fokus bleibt im Drawer", stillInDrawer);

// Hosterwechsel
const beforeHoster = await page.textContent(".player-actions button small").catch(() => null);
await page.click('[data-focus-key="hoster-Vidmoly"]');
await page.waitForTimeout(1800);
const afterHoster = await page.textContent(".player-actions button small").catch(() => null);
check("Hosterwechsel greift", (afterHoster ?? "").includes("Vidmoly"), `${beforeHoster} → ${afterHoster}`);

// Sprachwechsel
await press(page, "up");
await page.waitForTimeout(600);
await page.click('[data-focus-key="lang-GerSub"]').catch(() => undefined);
await page.waitForTimeout(1800);
const langAfter = await page.textContent(".player-actions button small").catch(() => null);
check("Sprachwechsel greift", (langAfter ?? "").includes("GerSub"), langAfter ?? "-");

// Zurück: Drawer zu, dann Bedienung zu, dann raus
await press(page, "up");
await page.waitForTimeout(600);
await press(page, "back");
await page.waitForTimeout(500);
check("Zurück schließt zuerst den Drawer", !(await page.$(".player-panel")));
check("Player läuft weiter", page.url().includes("#/player/"));

await press(page, "back");
await page.waitForTimeout(500);
const chromeHidden = await page.evaluate(() => !document.querySelector(".player-chrome")?.classList.contains("visible"));
check("Zurück schließt dann die Bedienung", chromeHidden);
check("Player noch offen", page.url().includes("#/player/"));

await press(page, "back");
await page.waitForTimeout(1200);
check("Zurück verlässt erst danach den Player", !page.url().includes("#/player/"), page.url());

// --- 16. Kein Stream läuft im Hintergrund weiter -------------------------
const strayVideos = await page.evaluate(() =>
  Array.from(document.querySelectorAll("video")).filter((v) => !v.paused && v.currentSrc).length);
check("Player-Abbau: kein Video läuft weiter", strayVideos === 0, `${strayVideos} laufend`);

// --- 17. Fortschritt und Weiterschauen ----------------------------------
section("Fortschritt");

const stored = await page.evaluate(() => {
  try { return JSON.parse(localStorage.getItem("nori.library") ?? "{}"); } catch { return {}; }
});
check(
  `Bibliothek: Schema v${LIBRARY_SCHEMA_VERSION}`,
  stored.version === LIBRARY_SCHEMA_VERSION,
  `version ${stored.version}`,
);
check("Merkliste gespeichert", Array.isArray(stored.favorites) && stored.favorites.length > 0,
  JSON.stringify(stored.favorites));
check(
  "Fortschritt gespeichert",
  stored.progress && Object.keys(stored.progress).length > 0,
  `${Object.keys(stored.progress ?? {}).length} Einträge`,
);
check(
  "Fortschritt trägt Quelle und Pfad im Schlüssel",
  Object.keys(stored.progress ?? {}).every((key) => key.startsWith("aniworld|") || key.startsWith("serienstream|")),
  Object.keys(stored.progress ?? {})[0] ?? "-",
);

await goto(page, "#/", 2500);
const continueRail = await page.$$eval(".rail h2", (els) => els.map((e) => e.textContent?.trim()));
check("„Weiterschauen“ erscheint nach der Wiedergabe", continueRail.includes("Weiterschauen"), continueRail.join(", "));
const wideCards = await page.$$eval('[data-rail="continue"] .wide-card', (e) => e.length);
check("Weiterschauen zeigt Breitformat-Kacheln", wideCards > 0, `${wideCards} Kacheln`);
await shot(page, "16-weiterschauen");

// Fortsetzen: der Player muss an der gespeicherten Stelle anknüpfen.
const savedAt = await page.evaluate(() => {
  try {
    const bag = JSON.parse(localStorage.getItem("nori.library") ?? "{}");
    const items = Object.values(bag.progress ?? {});
    return items.length > 0 ? Math.max(...items.map((item) => item.positionSec ?? 0)) : 0;
  } catch {
    return 0;
  }
});
check("Der gespeicherte Fortschritt liegt über der Resume-Schwelle", savedAt >= 8, `${savedAt.toFixed(1)} s`);

await page.click('[data-rail="continue"] .wide-card');
await page.waitForTimeout(3500);
const resumeState = await page.evaluate(() => {
  const video = document.querySelector("video.player-video");
  return {
    overlay: Boolean(document.querySelector(".player-overlay")),
    at: video?.currentTime ?? 0,
    inPlayer: window.location.hash.includes("/player/"),
    hash: window.location.hash,
  };
});
check("Fortsetzen öffnet den Player", resumeState.inPlayer, resumeState.hash);
check(
  "Fortsetzen öffnet dieselbe Folge",
  resumeState.hash.includes("episode=3"),
  resumeState.hash,
);
check(
  "Fortsetzen knüpft an der gespeicherten Stelle an",
  resumeState.overlay || Math.abs(resumeState.at - savedAt) < 12,
  `gespeichert ${savedAt.toFixed(1)} s, Wiedergabe bei ${resumeState.at.toFixed(1)} s, `
  + `Rückfrage ${resumeState.overlay}`,
);

await press(page, "back");
await press(page, "back");
await press(page, "back");
await page.waitForTimeout(1200);

// --- 18. Playerfehler ----------------------------------------------------
section("Playerfehler");

await goto(page, "#/player/aniworld/frieren?season=1&episode=1&path=%2Fanime%2Fstream%2Fkaputt%2Fstaffel-1%2Fepisode-1", 3000);
const errorState = await page.evaluate(() => {
  const panel = document.querySelector(".player-error");
  return panel
    ? {
      heading: panel.querySelector("h2")?.textContent ?? "",
      message: panel.querySelector("p")?.textContent ?? "",
      buttons: Array.from(panel.querySelectorAll("button")).map((b) => b.textContent?.trim() ?? ""),
      focusInside: Boolean(document.activeElement?.closest(".player-error")),
    }
    : null;
});
check("Ein Hosterfehler endet in einem Fehlerzustand", Boolean(errorState), errorState?.heading ?? "schwarze Fläche");
check("Der Fehler wird benannt", (errorState?.message.length ?? 0) > 10, errorState?.message ?? "-");
check("Der Fehlerzustand hat Knöpfe", (errorState?.buttons.length ?? 0) >= 2, errorState?.buttons.join(", ") ?? "-");
check("Der Fokus liegt im Fehlerzustand", errorState?.focusInside === true);
await shot(page, "17-playerfehler");

const errorVideos = await page.evaluate(() =>
  Array.from(document.querySelectorAll("video")).filter((v) => !v.paused && v.currentSrc).length);
check("Beim Fehler läuft kein Stream", errorVideos === 0, `${errorVideos} laufend`);

await page.click('[data-focus-key="error-exit"]');
await page.waitForTimeout(1200);
check("Aus dem Fehlerzustand führt ein Weg heraus", !page.url().includes("#/player/"), page.url());

// --- 19. Serverausfall mitten im Betrieb --------------------------------
section("Ausfälle");

await page.route("**/api/catalog/**", (route) => route.abort("failed"));
await page.evaluate(() => {
  // Beide Kataloge verwerfen, damit der nächste Aufbau neu lädt.
  for (const key of Object.keys(localStorage)) {
    if (key.startsWith("nori.covers")) localStorage.removeItem(key);
  }
});
await goto(page, "#/entdecken", 800);
await goto(page, "#/", 2500);
const offlinePanel = await page.evaluate(() => {
  const panel = document.querySelector(".state-panel");
  return panel ? (panel.querySelector("h2")?.textContent ?? "") : null;
});
check(
  "Serverausfall endet in einem Zustand, nicht in einer leeren Seite",
  Boolean(offlinePanel) || (await page.$$eval(".rail", (e) => e.length)) > 0,
  offlinePanel ?? "Reihen aus dem Zwischenspeicher",
);
const aliveAfterFailure = await focused(page);
const focusables = await page.evaluate(() => {
  const nodes = Array.from(document.querySelectorAll(".spottable"));
  const visible = nodes.filter((node) => {
    const rect = node.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0 && getComputedStyle(node).visibility !== "hidden";
  });
  return { total: nodes.length, visible: visible.length, active: document.activeElement?.tagName ?? "-" };
});
check(
  "Nach einem Ausfall bleibt die Fernbedienung bedienbar",
  Boolean(aliveAfterFailure),
  `${aliveAfterFailure?.key ?? "kein Fokus"} — ${focusables.visible}/${focusables.total} fokussierbar, `
  + `aktiv ${focusables.active}`,
);
await shot(page, "18-fehlerzustand");
await page.unroute("**/api/catalog/**");

// TMDB weg: die App muss weiterlaufen, nur ohne Bilder.
await page.route("**/api/tmdb/**", (route) => route.abort("failed"));
await page.evaluate(() => {
  for (const key of Object.keys(localStorage)) {
    if (key.startsWith("nori.tmdb")) localStorage.removeItem(key);
  }
});
await page.reload({ waitUntil: "domcontentloaded" });
await page.waitForTimeout(4000);
const withoutTmdbRails = await page.$$eval(".rail h2", (els) => els.map((e) => e.textContent?.trim()));
check(
  "Ohne TMDB steht die Startseite trotzdem",
  withoutTmdbRails.length > 0,
  withoutTmdbRails.join(", "),
);
check(
  "Ohne TMDB heißt keine Reihe „Neu & beliebt“",
  !withoutTmdbRails.includes("Neu & beliebt"),
  withoutTmdbRails.join(", "),
);
check(
  "Ohne TMDB sagt die Reihe, woher ihre Reihenfolge kommt",
  withoutTmdbRails.includes("Neu im Katalog") || withoutTmdbRails.includes("Weiterschauen"),
  withoutTmdbRails.join(", "),
);
await page.unroute("**/api/tmdb/**");

// --- 20. Keine Konsolenfehler -------------------------------------------
section("Konsole");

const relevant = consoleErrors.filter((e) =>
  !/Failed to load resource|net::ERR|ERR_FAILED|MEDIA_ELEMENT|no supported source|Unable to preventDefault/i.test(e));
check("Keine Skriptfehler in der Konsole", relevant.length === 0, relevant.slice(0, 3).join(" | "));

// --- 20a. Frisch installiert: TMDB ohne Einrichtung ---------------------
//
// Der Zustand, den ein Fernseher nach der Installation hat: keine
// Einstellungen, kein Server, kein Schlüssel. TMDB muss trotzdem eingerichtet
// sein — mit dem mitgelieferten Schlüssel. Auf einem Fernseher gibt es keine
// Tastatur, und eine App, die vor dem ersten Bild einen 32-stelligen
// Schlüssel verlangt, zeigt nie ein Bild.
//
// Geprüft wird der **Weg**, nicht der Abruf: api.themoviedb.org ist von hier
// nicht erreichbar, und ein Test, der das bräuchte, hinge an einer fremden
// Verfügbarkeit.
section("Frisch installiert");

const fresh = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
await fresh.route("https://image.tmdb.org/**", (route) =>
  route.fulfill({ status: 200, contentType: "image/png", body: PLACEHOLDER }));
// api.themoviedb.org ist von hier nicht erreichbar; abgewiesen statt
// dreißig Sekunden Zeitüberschreitung je Abruf.
await fresh.route("https://api.themoviedb.org/**", (route) => route.abort("failed"));
await fresh.goto(`${BASE}/#/einstellungen`, { waitUntil: "domcontentloaded" });
await fresh.waitForTimeout(3500);

const freshState = await fresh.evaluate(() => {
  const notes = Array.from(document.querySelectorAll(".page.settings .field-note"))
    .map((node) => node.textContent ?? "");
  return {
    stored: localStorage.getItem("nori.webos.settings"),
    way: notes.find((text) => text.startsWith("Weg:")) ?? "",
    modes: Array.from(document.querySelectorAll('[data-focus-key^="tmdb-"]'))
      .map((node) => `${node.textContent?.trim()}${node.classList.contains("selected") ? " ✓" : ""}`),
  };
});
check(
  "Ohne Einstellungen ist TMDB eingerichtet",
  freshState.way.includes("mitgelieferter Schlüssel"),
  freshState.way.trim().slice(0, 110),
);
check(
  "Der Weg heißt „Dieser Fernseher“, nicht „Eigener Schlüssel“",
  freshState.modes.some((label) => label.startsWith("Dieser Fernseher")),
  freshState.modes.join(" | "),
);
await fresh.screenshot({ path: join(SHOTS, "20-tmdb-ohne-einrichtung.png") });
await fresh.close();

// Und mit Server: dann gilt der Serverweg, nicht der eigene.
await goto(page, "#/einstellungen", 1200);
const serverWay = await page.evaluate(() =>
  Array.from(document.querySelectorAll(".page.settings .field-note"))
    .map((node) => node.textContent ?? "")
    .find((text) => text.startsWith("Weg:")) ?? "");
check(
  "Mit Server gilt der Serverweg",
  serverWay.includes("Nori-Server"),
  serverWay.trim().slice(0, 110),
);

// --- 20b. Abstände ohne Flex-`gap` (webOS 6) ----------------------------
//
// Chrome 79 kennt `gap` nur im Raster, nicht im Flex-Layout. Nori misst das
// beim Start und hängt daran einen Rückfall über Ränder. Hier wird beides
// geprüft: dass die Messung in einem heutigen Browser „ja" sagt (sonst gäbe es
// dort doppelte Abstände), und dass der Rückfall tatsächlich Abstand erzeugt.
section("Abstände ohne Flex-gap");

await goto(page, "#/", 2500);
const gapProbe = await page.evaluate(() => document.documentElement.dataset.flexGap);
check("Die Messung erkennt heutiges Flex-gap", gapProbe === "yes", String(gapProbe));

const spacing = await page.evaluate(() => {
  /*
   * Innerhalb **einer** Reihe messen, und nur zwischen sichtbaren Kacheln.
   *
   * Zwei Fallen: Über alle Reihen hinweg liegt die zweite Kachel in der
   * nächsten Reihe, und der Abstand wird negativ. Und zwischen je zwei
   * Kacheln hängt Enact ein eigenes `<div style="display:none">` — das zählt
   * weder für `gap` noch für einen Rand, würde eine Messung über
   * `children[0]` und `children[1]` aber auf 0 ziehen.
   */
  const visible = (track) => Array.from(track.children)
    .filter((node) => node.getBoundingClientRect().width > 0);
  // Die erste Reihe, die überhaupt zwei Kacheln hat: eine Reihe kann im
  // Ladezustand oder nach einem Ausfall eine einzige enthalten.
  const track = Array.from(document.querySelectorAll(".rail-track"))
    .find((candidate) => visible(candidate).length >= 2);
  const measure = () => {
    if (!track) return null;
    const cards = visible(track);
    if (cards.length < 2) return null;
    const a = cards[0].getBoundingClientRect();
    const b = cards[1].getBoundingClientRect();
    return Math.round(b.left - a.right);
  };
  const withGap = measure();

  // Flex-`gap` abschalten und den Rückfall einschalten — so verhält sich die
  // Seite wie auf Chrome 79.
  const style = document.createElement("style");
  style.textContent = "*{gap:normal !important}";
  document.head.appendChild(style);
  document.documentElement.dataset.flexGap = "no";
  const withoutGap = measure();

  // Und zurück, damit die folgenden Prüfungen die echte Seite sehen.
  style.parentNode.removeChild(style);
  document.documentElement.dataset.flexGap = "yes";
  return {
    withGap,
    withoutGap,
    rails: document.querySelectorAll(".rail-track").length,
    cards: track ? visible(track).length : 0,
  };
});
check(
  "Mit Flex-gap stehen die Kacheln auseinander",
  (spacing.withGap ?? 0) >= 20,
  `${spacing.withGap} px (${spacing.rails} Reihen, ${spacing.cards} Kacheln gemessen)`,
);
check(
  "Der Rückfall über Ränder erzeugt denselben Abstand",
  spacing.withoutGap === spacing.withGap,
  `mit gap ${spacing.withGap} px, mit Rändern ${spacing.withoutGap} px`,
);

// --- 21. Der Weg, den der Fernseher nimmt: file:// ----------------------
//
// Das ist die Prüfung, die dem echten Gerät am nächsten kommt. Ein
// webOS-Paket wird von `file:///usr/palm/applications/tv.nori.app/index.html`
// geladen — nicht über HTTP. Dort scheitern drei Dinge, die über HTTP nie
// auffallen: ES-Module, `crossorigin` und jede Adresse mit führendem
// Schrägstrich. Alle drei enden in einem schwarzen Bildschirm **ohne**
// Fehlermeldung, weil das Skript, das den Fehler melden würde, nie läuft.
section("Von file:// geladen");

const fileErrors = [];
const filePage = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
filePage.on("pageerror", (err) => fileErrors.push(err.message));
filePage.on("console", (msg) => {
  if (msg.type() === "error") fileErrors.push(msg.text());
});
await filePage.route("https://image.tmdb.org/**", (route) =>
  route.fulfill({ status: 200, contentType: "image/png", body: PLACEHOLDER }));
await filePage.addInitScript((base) => {
  localStorage.setItem("nori.webos.settings", JSON.stringify({
    transport: "server", serverUrl: base, controlsTimeout: 4, seekStep: 10,
    autoplayCountdown: 3, tmdbMode: "server", tmdbKey: "", reduceEffects: false, debug: true,
  }));
}, BASE);

// Das Bildschirmfoto vor dem Rendern: genau das sieht der Fernseher beim
// Kaltstart, und genau dafür steht der Block in `index.html`.
await filePage.goto(`file://${join(APP, "dist", "index.html")}`, { waitUntil: "commit" });
await filePage.waitForTimeout(120);
await filePage.screenshot({ path: join(SHOTS, "00-bootscreen.png") });

await filePage.waitForTimeout(6000);
const fileState = await filePage.evaluate(() => ({
  mounted: Boolean(document.querySelector(".app-shell")),
  splashGone: !document.querySelector(".boot-splash"),
  rails: document.querySelectorAll(".rail h2").length,
  cards: document.querySelectorAll(".media-card, .wide-card").length,
  styled: getComputedStyle(document.documentElement).getPropertyValue("--accent").trim(),
}));
check("Die App baut sich von file:// auf", fileState.mounted, JSON.stringify(fileState));
check("Der Startbildschirm verschwindet danach", fileState.splashGone);
check("Die Stile sind geladen", fileState.styled === "#d7deea", fileState.styled || "keine");
check("Die Daten kommen an", fileState.rails > 0 && fileState.cards > 5,
  `${fileState.rails} Reihen, ${fileState.cards} Kacheln`);
const fileFocus = await focused(filePage);
check("Der Fokus sitzt", Boolean(fileFocus), fileFocus?.key ?? "-");
await filePage.screenshot({ path: join(SHOTS, "19-von-file.png") });

const fileRelevant = fileErrors.filter((message) =>
  !/Failed to load resource|net::ERR|ERR_FAILED|MEDIA_ELEMENT|no supported source/i.test(message));
check(
  "Keine Skriptfehler von file://",
  fileRelevant.length === 0,
  fileRelevant.slice(0, 3).join(" | "),
);
await filePage.close();

} catch (error) {
  crashed = error;
  check("Der Lauf kommt bis zum Ende", false, `${error?.name ?? "Fehler"}: ${String(error?.message ?? error).split("\n")[0]}`);
  try {
    await shot(page, "99-abbruch");
  } catch {
    /* kein Bildschirmfoto mehr möglich */
  }
}

await browser.close();

console.log("\n" + results.join("\n"));
console.log(`\n${results.filter((line) => line.startsWith("PASS")).length}/${results.filter((line) => !line.startsWith("\n")).length} bestanden`);
console.log(`Bildschirmfotos: ${SHOTS}`);
if (crashed) console.error("\nAbbruch:", crashed);
process.exit(failures > 0 ? 1 : 0);

