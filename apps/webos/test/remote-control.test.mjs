// Fernbedienungsprüfung im echten Browser.
//
// Warum mit Tastencodes statt mit Mausklicks: was auf dem Fernseher passiert,
// entscheidet die Fernbedienung. Ein Test, der klickt, prüft einen Weg, den es
// dort nicht gibt — und übersieht genau die Fehler, die auf einem Fernseher
// wehtun: ein Element ohne Fokus, ein Fokus ohne Sichtbarkeit, eine
// Zurück-Taste, die zu weit springt.
//
// Voraussetzungen:
//
//     npm run build
//     node test/mock-server.mjs &        (in einem zweiten Fenster)
//     npm i -D playwright                (einmalig, ~50 MB Browser)
//     node test/remote-control.test.mjs
//
// Der Pfad zum Browser lässt sich über NORI_CHROMIUM setzen; ohne Angabe wird
// der von Playwright mitgelieferte benutzt.

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

const BASE = process.env.NORI_MOCK ?? "http://127.0.0.1:8799";
const results = [];
let failures = 0;

function check(name, ok, detail = "") {
  results.push(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? ` — ${detail}` : ""}`);
  if (!ok) failures += 1;
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

const KEY = { left: [37, "ArrowLeft"], up: [38, "ArrowUp"], right: [39, "ArrowRight"],
  down: [40, "ArrowDown"], ok: [13, "Enter"], back: [461, "GoBack"],
  play: [415, "MediaPlay"], pause: [19, "MediaPause"] };

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

const browser = await chromium.launch({
  executablePath: process.env.NORI_CHROMIUM || undefined,
  args: ["--no-sandbox", "--autoplay-policy=no-user-gesture-required"],
});
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });

const consoleErrors = [];
page.on("console", (msg) => {
  if (msg.type() === "error") consoleErrors.push(msg.text());
});
page.on("pageerror", (err) => consoleErrors.push(`pageerror: ${err.message}`));

// Server eintragen, bevor die App startet.
await page.addInitScript((base) => {
  localStorage.setItem("nori.webos.settings", JSON.stringify({
    transport: "server", serverUrl: base, controlsTimeout: 4, seekStep: 10,
    autoplayCountdown: 3, tmdbKey: "", reduceEffects: false, debug: true,
  }));
}, BASE);

await page.goto(BASE, { waitUntil: "domcontentloaded" });
await page.waitForTimeout(3000);

// --- 1. Startseite -------------------------------------------------------
const heroTitle = await page.textContent(".hero-copy h1").catch(() => null);
check("Startseite: Hero mit Titel", Boolean(heroTitle), heroTitle ?? "kein Hero");

const railTitles = await page.$$eval(".rail h2", (els) => els.map((e) => e.textContent));
check("Startseite: Reihen vorhanden", railTitles.length >= 2, railTitles.join(", "));

const cardCount = await page.$$eval(".media-card", (els) => els.length);
check("Startseite: Kacheln geladen", cardCount > 10, `${cardCount} Kacheln`);

// --- 2. Fokus ist immer irgendwo -----------------------------------------
let f = await focused(page);
check("Fokus nach dem Start gesetzt", Boolean(f), JSON.stringify(f));

// --- 3. Fokus-Stresstest: → → → ↓ ↓ ← ↑ ----------------------------------
let lostFocus = 0;
for (const seq of ["right", "right", "right", "down", "down", "left", "up", "down", "right", "right"]) {
  await press(page, seq);
  const cur = await focused(page);
  if (!cur) lostFocus += 1;
}
check("Fokus-Stresstest: nie ohne Fokus", lostFocus === 0, `${lostFocus} Verluste`);

const visibleFocus = await page.evaluate(() => {
  const el = document.activeElement;
  if (!el || el === document.body) return false;
  const r = el.getBoundingClientRect();
  return r.width > 0 && r.height > 0 && r.bottom > 0 && r.top < window.innerHeight;
});
check("Fokus ist sichtbar", visibleFocus);

// --- 4. Reihe entlang bis Karte 7, dann öffnen ---------------------------
await page.evaluate(() => {
  const card = document.querySelectorAll("#rail-trending .media-card, .rail-track .media-card")[0];
  card?.focus();
});
await page.waitForTimeout(200);
for (let i = 0; i < 6; i += 1) await press(page, "right");
const seventh = await focused(page);
check("Reihe: siebte Kachel erreichbar", Boolean(seventh?.key), seventh?.text ?? "-");

await press(page, "ok");
await page.waitForTimeout(1200);
const onDetails = page.url().includes("#/titel/");
check("Navigation: Detailseite geöffnet", onDetails, page.url());

// --- 5. Detailseite ------------------------------------------------------
const detailTitle = await page.textContent(".details-copy h1").catch(() => null);
check("Detailseite: Titel", Boolean(detailTitle), detailTitle ?? "-");
const seasonCount = await page.$$eval(".season-selector button", (e) => e.length);
check("Detailseite: Staffeln", seasonCount >= 2, `${seasonCount} Staffeln`);
const episodeCount = await page.$$eval(".episode-card", (e) => e.length);
check("Detailseite: Folgen", episodeCount >= 10, `${episodeCount} Folgen`);

// --- 6. Zurück → Fokus muss auf Karte 7 stehen ---------------------------
await press(page, "back");
await page.waitForTimeout(1400);
const backHome = !page.url().includes("#/titel/");
check("Zurück: wieder auf der Startseite", backHome, page.url());
const restored = await focused(page);
check(
  "Zurück: Fokus auf derselben Kachel",
  restored?.key === seventh?.key,
  `erwartet ${seventh?.key}, ist ${restored?.key}`,
);

// --- 7. Seitenleiste -----------------------------------------------------
for (let i = 0; i < 12; i += 1) await press(page, "left");
const inSidebar = await page.evaluate(() => Boolean(document.activeElement?.closest(".side-nav")));
check("Seitenleiste über Links erreichbar", inSidebar);
const expanded = await page.evaluate(() => document.querySelector(".side-nav")?.classList.contains("expanded"));
check("Seitenleiste klappt bei Fokus auf", Boolean(expanded));

// --- 8. Alle Seiten anfahren --------------------------------------------
const pages = [
  ["/entdecken", ".page.explore", "Entdecken"],
  ["/kalender", ".page.calendar", "Kalender"],
  ["/suche", ".page.search", "Suche"],
  ["/merkliste", ".media-grid, .state-panel", "Merkliste"],
  ["/verlauf", ".page.history", "Verlauf"],
  ["/einstellungen", ".page.settings", "Einstellungen"],
];
for (const [route, selector, label] of pages) {
  await page.evaluate((r) => { window.location.hash = `#${r}`; }, route);
  await page.waitForTimeout(1000);
  const present = await page.$(selector);
  const hasFocus = await focused(page);
  check(`Seite ${label} rendert`, Boolean(present));
  check(`Seite ${label} hat Fokus`, Boolean(hasFocus), hasFocus?.key ?? "-");
}

// --- 9. Suche ------------------------------------------------------------
await page.evaluate(() => { window.location.hash = "#/suche"; });
await page.waitForTimeout(800);
await page.fill(".search-bar input", "one");
await page.waitForTimeout(900);
const hits = await page.$$eval(".media-grid .media-card", (e) => e.length);
check("Suche liefert Treffer", hits > 0, `${hits} Treffer`);

// --- 10. Merkliste über Detailseite --------------------------------------
await page.evaluate(() => { window.location.hash = "#/titel/aniworld/frieren"; });
await page.waitForTimeout(1200);
await page.click('[data-focus-key="favorite"]');
await page.waitForTimeout(400);
const favLabel = await page.textContent('[data-focus-key="favorite"]');
check("Merkliste: Titel aufgenommen", (favLabel ?? "").includes("Auf Merkliste"), favLabel ?? "-");
await page.evaluate(() => { window.location.hash = "#/merkliste"; });
await page.waitForTimeout(800);
const favCount = await page.$$eval(".media-grid .media-card", (e) => e.length);
check("Merkliste: Seite zeigt den Titel", favCount === 1, `${favCount} Einträge`);

// --- 11. Player ----------------------------------------------------------
await page.evaluate(() => { window.location.hash = "#/titel/aniworld/frieren"; });
await page.waitForTimeout(1200);
await page.click('[data-focus-key="episode-3"]');
await page.waitForTimeout(2000);
const inPlayer = page.url().includes("#/player/");
check("Player: geöffnet", inPlayer, page.url());
const hasVideo = await page.$("video.player-video");
check("Player: Videoelement vorhanden", Boolean(hasVideo));
const chromeVisible = await page.evaluate(() => document.querySelector(".player-chrome")?.classList.contains("visible"));
check("Player: Bedienung anfangs sichtbar", Boolean(chromeVisible));
const hosterLabel = await page.textContent(".player-actions button small").catch(() => null);
check("Player: Hoster aufgelöst", (hosterLabel ?? "").includes("VOE"), hosterLabel ?? "-");

// Drawer über Pfeil hoch
await press(page, "up");
await page.waitForTimeout(600);
const drawerOpen = await page.$(".player-panel");
check("Player: Drawer über Pfeil hoch", Boolean(drawerOpen));
const drawerFocus = await page.evaluate(() => Boolean(document.activeElement?.closest(".player-panel")));
check("Player: Fokus liegt im Drawer", drawerFocus);

// Fokus darf den Drawer nicht verlassen
for (const seq of ["left", "left", "left", "down", "down", "up"]) await press(page, seq);
const stillInDrawer = await page.evaluate(() => Boolean(document.activeElement?.closest(".player-panel")));
check("Player: Fokus bleibt im Drawer", stillInDrawer);

// Hosterwechsel
const before = await page.textContent(".player-actions button small").catch(() => null);
await page.click('[data-focus-key="hoster-Vidmoly"]');
await page.waitForTimeout(1600);
const after = await page.textContent(".player-actions button small").catch(() => null);
check("Player: Hosterwechsel greift", (after ?? "").includes("Vidmoly"), `${before} → ${after}`);

// Sprachwechsel
await press(page, "up");
await page.waitForTimeout(500);
await page.click('[data-focus-key="lang-GerSub"]').catch(() => undefined);
await page.waitForTimeout(1600);
const langAfter = await page.textContent(".player-actions button small").catch(() => null);
check("Player: Sprachwechsel greift", (langAfter ?? "").includes("GerSub"), langAfter ?? "-");

// Zurück: Drawer zu, dann Bedienung zu, dann raus
await press(page, "up");
await page.waitForTimeout(500);
await press(page, "back");
await page.waitForTimeout(400);
const drawerClosed = !(await page.$(".player-panel"));
check("Zurück: schließt zuerst den Drawer", drawerClosed);
const stillPlayer1 = page.url().includes("#/player/");
check("Zurück: Player läuft weiter", stillPlayer1);

await press(page, "back");
await page.waitForTimeout(400);
const chromeHidden = await page.evaluate(() => !document.querySelector(".player-chrome")?.classList.contains("visible"));
check("Zurück: schließt dann die Bedienung", chromeHidden);
const stillPlayer2 = page.url().includes("#/player/");
check("Zurück: Player noch offen", stillPlayer2);

await press(page, "back");
await page.waitForTimeout(1000);
const leftPlayer = !page.url().includes("#/player/");
check("Zurück: verlässt erst danach den Player", leftPlayer, page.url());

// --- 12. Kein Stream läuft im Hintergrund weiter -------------------------
const strayVideos = await page.evaluate(() =>
  Array.from(document.querySelectorAll("video")).filter((v) => !v.paused && v.currentSrc).length);
check("Player-Abbau: kein Video läuft weiter", strayVideos === 0, `${strayVideos} laufend`);

// --- 13. Fortschritt gespeichert ----------------------------------------
const stored = await page.evaluate(() => {
  try { return JSON.parse(localStorage.getItem("nori.library") ?? "{}"); } catch { return {}; }
});
// Die Zahl gehört zu `LibraryStore.schemaVersion` und `LIBRARY_SCHEMA_VERSION`;
// beide stehen auf 5, ebenso `config/contract.json`. Diese Zeile stand noch auf
// 4 und hätte eine echte Schemaregression nicht mehr bemerkt.
check("Bibliothek: Schema v5", stored.version === 5, `version ${stored.version}`);
check("Bibliothek: Merkliste gespeichert", Array.isArray(stored.favorites) && stored.favorites.length > 0,
  JSON.stringify(stored.favorites));

// --- 14. Keine Konsolenfehler -------------------------------------------
const relevant = consoleErrors.filter((e) => !/Failed to load resource|net::ERR|MEDIA_ELEMENT|no supported source/i.test(e));
check("Keine Skriptfehler in der Konsole", relevant.length === 0, relevant.slice(0, 3).join(" | "));

await page.screenshot({ path: "shot-start.png" });
await page.evaluate(() => { window.location.hash = "#/titel/aniworld/frieren"; });
await page.waitForTimeout(1400);
await page.screenshot({ path: "shot-details.png" });

await browser.close();

console.log("\n" + results.join("\n"));
console.log(`\n${results.length - failures}/${results.length} bestanden`);
process.exit(failures > 0 ? 1 : 0);
