// VOE legt die Adresse verschlüsselt in ein JSON-Script-Tag statt sie in den
// Player zu schreiben. Verfahren wie in `HosterResolver.decodeVoe`.

const VOE_TOKENS = ["@$", "^^", "~@", "%?", "*~", "!!", "#&"];

export interface VoeConfig {
  source?: string;
  direct?: string;
}

export function rot13(input: string): string {
  return input.replace(/[a-zA-Z]/g, (ch) => {
    const code = ch.charCodeAt(0);
    if (code >= 65 && code <= 90) return String.fromCharCode(((code - 65 + 13) % 26) + 65);
    return String.fromCharCode(((code - 97 + 13) % 26) + 97);
  });
}

export function padBase64(s: string): string {
  const pad = (4 - (s.length % 4)) % 4;
  return s + "=".repeat(pad);
}

/** Base64 → Bytes, ohne `Buffer` (der Fernseher hat keinen). */
function base64ToBytes(value: string): Uint8Array | null {
  try {
    const binary = atob(padBase64(value.replace(/\s+/g, "")));
    const out = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) out[i] = binary.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

export function decodeVoe(encrypted: string): Record<string, unknown> | null {
  let s = rot13(encrypted);
  for (const token of VOE_TOKENS) s = s.split(token).join("_");
  s = s.split("_").join("");
  const step1 = base64ToBytes(s);
  if (!step1) return null;
  // Latin-1: jedes Byte ist ein Zeichen. Ohne das käme UTF-8-Decodierung
  // dazwischen und die Rückwärtsdrehung liefe auf falschen Zeichen.
  let shifted = "";
  for (const byte of step1) shifted += String.fromCharCode((byte - 3) & 0xff);
  const reversed = shifted.split("").reverse().join("");
  const jsonBytes = base64ToBytes(reversed);
  if (!jsonBytes) return null;
  // Die Nutzlast ist UTF-8. Zeichenweise zusammensetzen ergäbe bei Umlauten
  // und japanischen Titeln Mojibake — und JSON.parse bricht daran ab.
  try {
    const json = new TextDecoder("utf-8").decode(jsonBytes);
    const obj = JSON.parse(json) as unknown;
    return typeof obj === "object" && obj ? (obj as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

export function extractVoe(html: string): VoeConfig | null {
  const regex = /<script[^>]*type=["']application\/json["'][^>]*>([\s\S]*?)<\/script>/gi;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(html)) !== null) {
    const blob = match[1].trim();
    let parsed: unknown;
    try {
      parsed = JSON.parse(blob);
    } catch {
      continue;
    }
    const encrypted = Array.isArray(parsed) && typeof parsed[0] === "string" ? parsed[0] : null;
    if (!encrypted) continue;
    const cfg = decodeVoe(encrypted);
    if (!cfg) continue;
    const source = typeof cfg.source === "string" ? cfg.source : undefined;
    const direct = typeof cfg.direct_access_url === "string" ? cfg.direct_access_url : undefined;
    if (source || direct) return { source, direct };
  }
  return null;
}
