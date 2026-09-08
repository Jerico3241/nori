// Ein HTML-Parser für beide Laufzeiten.
//
// Der Swift-Kern benutzt SwiftSoup. Im Browser gibt es `DOMParser` nativ, in
// Node nicht — dort setzt `services/nori-api` beim Start `linkedom` ein. Die
// Parser selbst sehen davon nichts: sie arbeiten gegen die normale DOM-API
// (`querySelectorAll`, `getAttribute`, `textContent`) und laufen deshalb
// unverändert auf dem Fernseher wie auf dem Server.

export type HtmlParser = (html: string) => Document;

let custom: HtmlParser | null = null;

/** Von Node aus aufrufen, bevor ein Parser benutzt wird. */
export function setHtmlParser(parser: HtmlParser): void {
  custom = parser;
}

export function parseHtml(html: string): Document {
  if (custom) return custom(html);
  const DP = (globalThis as { DOMParser?: new () => DOMParser }).DOMParser;
  if (!DP) {
    throw new Error(
      "Kein HTML-Parser vorhanden. In Node vor dem ersten Aufruf setHtmlParser(...) setzen.",
    );
  }
  return new DP().parseFromString(html, "text/html");
}

/** `element.textContent`, aber mit zusammengefassten Leerzeichen wie SwiftSoups `text()`. */
export function text(el: Element | null | undefined): string {
  if (!el) return "";
  return (el.textContent ?? "").replace(/\s+/g, " ").trim();
}

export function attr(el: Element | null | undefined, name: string): string {
  if (!el) return "";
  return (el.getAttribute(name) ?? "").trim();
}

export function all(root: ParentNode, selector: string): Element[] {
  return Array.from(root.querySelectorAll(selector));
}

export function first(root: ParentNode, selector: string): Element | null {
  return root.querySelector(selector);
}

/** Wie `String?.nilIfEmpty` im Swift-Kern. */
export function nilIfEmpty(value: string | null | undefined): string | null {
  const t = (value ?? "").trim();
  return t.length === 0 ? null : t;
}
