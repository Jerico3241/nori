// In Node gibt es keinen DOMParser. `linkedom` liefert einen — dieselbe
// Umschaltung, die auch `services/nori-api` beim Start vornimmt.
import { parseHTML } from "linkedom";
import { setHtmlParser } from "../src/dom.js";

setHtmlParser((html: string) => parseHTML(html).document as unknown as Document);
