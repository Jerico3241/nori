// QR-Code, im Gerät gerechnet.
//
// Auf dem Fernseher soll niemand eine Adresse mit der Fernbedienung eintippen.
// Ein QR-Code löst das — aber nur, wenn er *hier* entsteht. Ein Aufruf gegen
// einen QR-Dienst im Netz hiesse, die Anmeldeadresse samt Gerätecode an einen
// Dritten zu schicken, und genau das darf beim Anmelden nicht passieren.
//
// Deshalb dieser Encoder: reines TypeScript, keine Abhängigkeit, kein Abruf.
// Er kann genau so viel, wie Nori braucht — Byte-Modus, Fehlerkorrektur M,
// Fassungen 1 bis 10. Das reicht für gut zweihundert Zeichen; die längste
// Adresse, die Google für diesen Fluss ausgibt, liegt bei etwa fünfzig.
//
// Geprüft wird er nicht gegen sich selbst, sondern gegen Matrizen einer
// unabhängigen Umsetzung (`segno`), die als Festwerte in
// `test/qr.test.ts` liegen. Ein Encoder, der nur gegen seine eigenen Regeln
// getestet ist, beweist nichts: ein falsch gesetztes Muster wäre in beiden
// Richtungen gleich falsch.
//
// Quelle für Tabellen und Ablauf: ISO/IEC 18004.

/** Ein fertiger QR-Code: quadratisch, `true` heisst dunkel. */
export interface QrCode {
  /** Kantenlänge in Modulen, ohne den weissen Rand. */
  readonly size: number;
  /** `modules[zeile][spalte]`. */
  readonly modules: readonly (readonly boolean[])[];
  /** Welche Fassung gewählt wurde. Nur für Diagnose und Tests. */
  readonly version: number;
  /** Welche Maske gewonnen hat. Nur für Diagnose und Tests. */
  readonly mask: number;
}

export class QrError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "QrError";
  }
}

/** Gesamtzahl der Codewörter je Fassung (Daten + Fehlerkorrektur). */
const TOTAL_CODEWORDS = [0, 26, 44, 70, 100, 134, 172, 196, 242, 292, 346];

/**
 * Blockaufbau für Fehlerkorrekturgrad M.
 *
 * `[ecPerBlock, blocks1, data1, blocks2, data2]`. Die zweite Gruppe hat
 * jeweils genau ein Datencodewort mehr; das ist keine Vereinfachung, sondern
 * die Bauart der Norm.
 */
const BLOCKS_M: readonly (readonly [number, number, number, number, number])[] = [
  [0, 0, 0, 0, 0],
  [10, 1, 16, 0, 0],
  [16, 1, 28, 0, 0],
  [26, 1, 44, 0, 0],
  [18, 2, 32, 0, 0],
  [24, 2, 43, 0, 0],
  [16, 4, 27, 0, 0],
  [18, 4, 31, 0, 0],
  [22, 2, 38, 2, 39],
  [22, 3, 36, 2, 37],
  [26, 4, 43, 1, 44],
];

/** Mittelpunkte der Ausrichtungsmuster je Fassung. */
const ALIGNMENT: readonly (readonly number[])[] = [
  [], [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34],
  [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50],
];

/**
 * Restbits nach den Codewörtern.
 *
 * Die Datenfläche ist nicht durch acht teilbar. Die übrigen Bits bleiben null
 * und werden trotzdem von der Maske erfasst — wer sie weglässt, verschiebt
 * alles Folgende.
 */
const REMAINDER_BITS = [0, 0, 7, 7, 7, 7, 7, 0, 0, 0, 0];

const MAX_VERSION = 10;

/** Fehlerkorrekturgrad M, wie im Formatfeld kodiert. */
const EC_LEVEL_M = 0b00;

// MARK: - GF(256)

// Das Feld, in dem Reed-Solomon rechnet: Polynome modulo 0x11d, Erzeuger 2.
const EXP = new Uint8Array(512);
const LOG = new Uint8Array(256);
{
  let value = 1;
  for (let i = 0; i < 255; i += 1) {
    EXP[i] = value;
    LOG[value] = i;
    value <<= 1;
    if (value & 0x100) value ^= 0x11d;
  }
  for (let i = 255; i < 512; i += 1) EXP[i] = EXP[i - 255];
}

function gfMul(a: number, b: number): number {
  if (a === 0 || b === 0) return 0;
  return EXP[LOG[a] + LOG[b]];
}

/** Das Erzeugerpolynom für `degree` Fehlerkorrektur-Codewörter. */
function generatorPolynomial(degree: number): Uint8Array {
  let poly = new Uint8Array([1]);
  for (let i = 0; i < degree; i += 1) {
    const next = new Uint8Array(poly.length + 1);
    for (let j = 0; j < poly.length; j += 1) {
      next[j] ^= poly[j];
      next[j + 1] ^= gfMul(poly[j], EXP[i]);
    }
    poly = next;
  }
  return poly;
}

/** Die Fehlerkorrektur-Codewörter eines Datenblocks. */
function errorCorrection(data: Uint8Array, ecCount: number): Uint8Array {
  const generator = generatorPolynomial(ecCount);
  const result = new Uint8Array(ecCount);
  for (const byte of data) {
    const factor = byte ^ result[0];
    result.copyWithin(0, 1);
    result[ecCount - 1] = 0;
    for (let i = 0; i < ecCount; i += 1) {
      result[i] ^= gfMul(generator[i + 1], factor);
    }
  }
  return result;
}

// MARK: - BCH

/**
 * Das Formatfeld: fünf Bits Nutzlast, zehn Bits BCH, danach maskiert.
 *
 * Gerechnet statt abgeschrieben. Eine Tabelle mit 32 Bitfolgen ist genau die
 * Art Datenmenge, in der sich ein Tippfehler versteckt, den kein Test findet,
 * der dieselbe Tabelle benutzt.
 */
function formatBits(ecLevel: number, mask: number): number {
  const data = (ecLevel << 3) | mask;
  let rest = data << 10;
  for (let i = 14; i >= 10; i -= 1) {
    if (rest & (1 << i)) rest ^= 0b101_0011_0111 << (i - 10);
  }
  return ((data << 10) | rest) ^ 0b101_0100_0001_0010;
}

/** Das Fassungsfeld: sechs Bits Nutzlast, zwölf Bits BCH. Erst ab Fassung 7. */
function versionBits(version: number): number {
  let rest = version << 12;
  for (let i = 17; i >= 12; i -= 1) {
    if (rest & (1 << i)) rest ^= 0b1_1111_0010_0101 << (i - 12);
  }
  return (version << 12) | rest;
}

// MARK: - Bitstrom

class BitBuffer {
  readonly bits: number[] = [];

  push(value: number, length: number): void {
    for (let i = length - 1; i >= 0; i -= 1) this.bits.push((value >>> i) & 1);
  }
}

// MARK: - Kodieren

/**
 * Einen QR-Code für `text` rechnen.
 *
 * Immer Byte-Modus: der Text ist eine Adresse, und dafür ist der
 * alphanumerische Modus ohnehin nicht zulässig (Kleinbuchstaben, `:`, `?`, `=`
 * kommen dort nicht vor). Ein zweiter Modus wäre Code, der nie läuft.
 */
export function encodeQrCode(text: string, options: { mask?: number } = {}): QrCode {
  const data = new TextEncoder().encode(text);
  const version = smallestVersion(data.length);
  const codewords = assembleCodewords(data, version);
  return placeAndMask(codewords, version, options.mask);
}

function dataCodewordCount(version: number): number {
  const [ec, blocks1, data1, blocks2, data2] = BLOCKS_M[version];
  void ec;
  return blocks1 * data1 + blocks2 * data2;
}

function characterCountBits(version: number): number {
  return version < 10 ? 8 : 16;
}

function smallestVersion(byteLength: number): number {
  for (let version = 1; version <= MAX_VERSION; version += 1) {
    const needed = 4 + characterCountBits(version) + byteLength * 8;
    if (needed <= dataCodewordCount(version) * 8) return version;
  }
  throw new QrError(`Zu viele Zeichen für einen QR-Code dieser Grösse (${byteLength} Byte).`);
}

/** Datenbits, Füllung, Fehlerkorrektur und Verschränkung. */
function assembleCodewords(data: Uint8Array, version: number): Uint8Array {
  const capacity = dataCodewordCount(version);
  const buffer = new BitBuffer();
  buffer.push(0b0100, 4);
  buffer.push(data.length, characterCountBits(version));
  for (const byte of data) buffer.push(byte, 8);

  // Abschluss: bis zu vier Nullen, dann auf die Bytegrenze.
  const terminator = Math.min(4, capacity * 8 - buffer.bits.length);
  buffer.push(0, terminator);
  while (buffer.bits.length % 8 !== 0) buffer.push(0, 1);

  const bytes = new Uint8Array(capacity);
  for (let i = 0; i < buffer.bits.length; i += 8) {
    let byte = 0;
    for (let j = 0; j < 8; j += 1) byte = (byte << 1) | buffer.bits[i + j];
    bytes[i / 8] = byte;
  }
  // Die vorgeschriebenen Füllbytes, abwechselnd. Nicht Nullen: eine lange
  // Nullfläche wäre für den Decoder ein schwer zu lesendes Muster.
  for (let i = buffer.bits.length / 8; i < capacity; i += 1) {
    bytes[i] = i % 2 === (buffer.bits.length / 8) % 2 ? 0xec : 0x11;
  }

  const [ecPerBlock, blocks1, data1, blocks2, data2] = BLOCKS_M[version];
  const groups: Uint8Array[] = [];
  let offset = 0;
  for (let i = 0; i < blocks1; i += 1) {
    groups.push(bytes.subarray(offset, offset + data1));
    offset += data1;
  }
  for (let i = 0; i < blocks2; i += 1) {
    groups.push(bytes.subarray(offset, offset + data2));
    offset += data2;
  }
  const parity = groups.map((block) => errorCorrection(block, ecPerBlock));

  // Verschränken: erst je Block das erste Datencodewort, dann das zweite, und
  // danach dasselbe für die Fehlerkorrektur. Ohne das trifft ein Kratzer über
  // dem Code einen einzigen Block vollständig statt alle ein wenig.
  const result = new Uint8Array(TOTAL_CODEWORDS[version]);
  let index = 0;
  const longest = Math.max(data1, data2);
  for (let column = 0; column < longest; column += 1) {
    for (const block of groups) {
      if (column < block.length) result[index++] = block[column];
    }
  }
  for (let column = 0; column < ecPerBlock; column += 1) {
    for (const block of parity) result[index++] = block[column];
  }
  return result;
}

// MARK: - Matrix

type Grid = boolean[][];

function emptyGrid(size: number): Grid {
  return Array.from({ length: size }, () => new Array<boolean>(size).fill(false));
}

/** Die Funktionsmuster setzen und festhalten, welche Felder belegt sind. */
function functionPatterns(version: number): { modules: Grid; reserved: Grid } {
  const size = version * 4 + 17;
  const modules = emptyGrid(size);
  const reserved = emptyGrid(size);

  const set = (row: number, column: number, dark: boolean) => {
    modules[row][column] = dark;
    reserved[row][column] = true;
  };

  // Die drei Suchmuster mit ihren Trennlinien.
  for (const [top, left] of [[0, 0], [0, size - 7], [size - 7, 0]] as const) {
    for (let row = -1; row <= 7; row += 1) {
      for (let column = -1; column <= 7; column += 1) {
        const r = top + row;
        const c = left + column;
        if (r < 0 || r >= size || c < 0 || c >= size) continue;
        const ring = Math.max(Math.abs(row - 3), Math.abs(column - 3));
        set(r, c, ring !== 2 && ring <= 3);
      }
    }
  }

  // Taktmuster: Zeile und Spalte 6.
  for (let i = 8; i < size - 8; i += 1) {
    const dark = i % 2 === 0;
    set(6, i, dark);
    set(i, 6, dark);
  }

  // Ausrichtungsmuster, ausser dort, wo ein Suchmuster liegt.
  const centres = ALIGNMENT[version];
  for (const row of centres) {
    for (const column of centres) {
      const onFinder = (row === 6 && column === 6)
        || (row === 6 && column === size - 7)
        || (row === size - 7 && column === 6);
      if (onFinder) continue;
      for (let dr = -2; dr <= 2; dr += 1) {
        for (let dc = -2; dc <= 2; dc += 1) {
          set(row + dr, column + dc, Math.max(Math.abs(dr), Math.abs(dc)) !== 1);
        }
      }
    }
  }

  // Die Felder des Formatfelds freihalten; gefüllt wird sie je Maske.
  for (let i = 0; i < 9; i += 1) {
    if (!reserved[8][i]) set(8, i, false);
    if (!reserved[i][8]) set(i, 8, false);
  }
  for (let i = 0; i < 8; i += 1) {
    if (!reserved[8][size - 1 - i]) set(8, size - 1 - i, false);
    if (!reserved[size - 1 - i][8]) set(size - 1 - i, 8, false);
  }
  // Das immer dunkle Modul.
  set(size - 8, 8, true);

  if (version >= 7) {
    const bits = versionBits(version);
    for (let i = 0; i < 18; i += 1) {
      const dark = ((bits >>> i) & 1) === 1;
      set(size - 11 + (i % 3), Math.floor(i / 3), dark);
      set(Math.floor(i / 3), size - 11 + (i % 3), dark);
    }
  }

  return { modules, reserved };
}

/** Die Codewörter im Zickzack von rechts unten nach links oben einlegen. */
function placeData(modules: Grid, reserved: Grid, codewords: Uint8Array, version: number): void {
  const size = modules.length;
  const total = codewords.length * 8 + REMAINDER_BITS[version];
  let bit = 0;

  for (let right = size - 1; right >= 1; right -= 2) {
    // Spalte 6 ist das Taktmuster; die Doppelspalten links davon verschieben
    // sich dadurch um eins.
    const column = right <= 6 ? right - 1 : right;
    for (let step = 0; step < size; step += 1) {
      const upwards = ((column + 1) & 2) === 0;
      const row = upwards ? size - 1 - step : step;
      for (const c of [column, column - 1]) {
        if (c < 0 || reserved[row][c]) continue;
        if (bit < total) {
          const index = bit >>> 3;
          modules[row][c] = index < codewords.length
            && ((codewords[index] >>> (7 - (bit & 7))) & 1) === 1;
        }
        bit += 1;
      }
    }
  }
}

function maskBit(mask: number, row: number, column: number): boolean {
  switch (mask) {
    case 0: return (row + column) % 2 === 0;
    case 1: return row % 2 === 0;
    case 2: return column % 3 === 0;
    case 3: return (row + column) % 3 === 0;
    case 4: return (Math.floor(row / 2) + Math.floor(column / 3)) % 2 === 0;
    case 5: return ((row * column) % 2) + ((row * column) % 3) === 0;
    case 6: return (((row * column) % 2) + ((row * column) % 3)) % 2 === 0;
    default: return (((row + column) % 2) + ((row * column) % 3)) % 2 === 0;
  }
}

function writeFormat(modules: Grid, mask: number): void {
  const size = modules.length;
  const bits = formatBits(EC_LEVEL_M, mask);
  const bit = (index: number) => ((bits >>> index) & 1) === 1;

  // Erste Kopie: senkrecht neben dem linken oberen Suchmuster nach unten,
  // dann um die Ecke nach rechts. Die Reihenfolge der Bits ist die der Norm
  // und **nicht** spiegelbar: Zeile 8 und Spalte 8 tragen unterschiedliche
  // Abschnitte derselben Bitfolge.
  for (let i = 0; i <= 5; i += 1) modules[i][8] = bit(i);
  modules[7][8] = bit(6);
  modules[8][8] = bit(7);
  modules[8][7] = bit(8);
  for (let i = 9; i < 15; i += 1) modules[8][14 - i] = bit(i);

  // Zweite Kopie: geteilt auf die beiden anderen Ecken.
  for (let i = 0; i < 8; i += 1) modules[8][size - 1 - i] = bit(i);
  for (let i = 8; i < 15; i += 1) modules[size - 15 + i][8] = bit(i);
  modules[size - 8][8] = true;
}

function placeAndMask(codewords: Uint8Array, version: number, forced?: number): QrCode {
  let best: { modules: Grid; mask: number; penalty: number } | null = null;
  const candidates = forced === undefined ? [0, 1, 2, 3, 4, 5, 6, 7] : [forced];

  for (const mask of candidates) {
    const { modules, reserved } = functionPatterns(version);
    placeData(modules, reserved, codewords, version);
    for (let row = 0; row < modules.length; row += 1) {
      for (let column = 0; column < modules.length; column += 1) {
        if (!reserved[row][column] && maskBit(mask, row, column)) {
          modules[row][column] = !modules[row][column];
        }
      }
    }
    writeFormat(modules, mask);
    const penalty = penaltyScore(modules);
    if (!best || penalty < best.penalty) best = { modules, mask, penalty };
  }

  const chosen = best as { modules: Grid; mask: number; penalty: number };
  return {
    size: chosen.modules.length,
    modules: chosen.modules,
    version,
    mask: chosen.mask,
  };
}

// MARK: - Maskenbewertung

const PENALTY_RUN = 3;
const PENALTY_BLOCK = 3;
const PENALTY_FINDER_LIKE = 40;
const PENALTY_BALANCE = 10;

/**
 * Die vier Straffunktionen der Norm.
 *
 * Sie entscheiden, welche der acht Masken genommen wird. Ohne sie liesse sich
 * ein Code erzeugen, der formal gültig, aber für eine Kamera schwer zu lesen
 * ist — grosse einfarbige Flächen, oder Muster, die einem Suchmuster gleichen
 * und den Decoder in die falsche Ecke schicken.
 *
 * Die dritte Regel ist die, an der sich Umsetzungen unterscheiden: Zählt der
 * weisse Rand *ausserhalb* des Symbols als helle Fläche? Hier ja — so steht
 * es in der Norm („preceded or followed by light area 4 modules wide"), und
 * so rechnet auch die Referenzumsetzung von Nayuki, gegen deren Matrizen
 * dieser Encoder geprüft wird.
 */
function penaltyScore(modules: Grid): number {
  const size = modules.length;
  let score = 0;

  for (let i = 0; i < size; i += 1) {
    for (const line of [modules[i], modules.map((row) => row[i])]) {
      let runColour = false;
      let runLength = 0;
      const history = [0, 0, 0, 0, 0, 0, 0];

      for (let j = 0; j < size; j += 1) {
        if (line[j] === runColour) {
          runLength += 1;
          // Regel 1: fünf gleiche in Folge kosten 3, jedes weitere 1.
          if (runLength === 5) score += PENALTY_RUN;
          else if (runLength > 5) score += 1;
        } else {
          addRun(history, runLength, size);
          // Regel 3 wird nur beim Ende einer **hellen** Strecke geprüft: erst
          // dann liegt ein vollständiges 1:1:3:1:1 in der Vorgeschichte.
          if (!runColour) score += countFinderLike(history) * PENALTY_FINDER_LIKE;
          runColour = line[j];
          runLength = 1;
        }
      }
      score += terminateRuns(history, runColour, runLength, size) * PENALTY_FINDER_LIKE;
    }
  }

  // Regel 2: gleichfarbige Zweier-Quadrate.
  for (let row = 0; row < size - 1; row += 1) {
    for (let column = 0; column < size - 1; column += 1) {
      const value = modules[row][column];
      if (value === modules[row][column + 1]
        && value === modules[row + 1][column]
        && value === modules[row + 1][column + 1]) score += PENALTY_BLOCK;
    }
  }

  // Regel 4: Abweichung vom halben Dunkelanteil, in Fünf-Prozent-Schritten.
  let dark = 0;
  for (const row of modules) for (const value of row) if (value) dark += 1;
  const total = size * size;
  const steps = Math.ceil(Math.abs(dark * 20 - total * 10) / total) - 1;
  score += Math.max(0, steps) * PENALTY_BALANCE;

  return score;
}

/**
 * Eine abgeschlossene Strecke in die Vorgeschichte schieben.
 *
 * Ist die Vorgeschichte noch leer, war diese Strecke die erste der Zeile — und
 * links davon liegt der weisse Rand des Symbols. Er wird mit der Kantenlänge
 * angesetzt: breiter als jede Strecke, die innerhalb noch folgen kann.
 */
function addRun(history: number[], length: number, size: number): void {
  let value = length;
  if (history[0] === 0) value += size;
  history.copyWithin(1, 0, history.length - 1);
  history[0] = value;
}

/** Die letzte Strecke abschliessen und den Rand rechts dazunehmen. */
function terminateRuns(history: number[], colour: boolean, length: number, size: number): number {
  let remaining = length;
  if (colour) {
    addRun(history, remaining, size);
    remaining = 0;
  }
  addRun(history, remaining + size, size);
  return countFinderLike(history);
}

/**
 * Wie oft das Verhältnis 1:1:3:1:1 mit einer hellen Fläche daneben vorkommt.
 *
 * Zweimal zählt es, wenn auf **beiden** Seiten genug Helligkeit liegt — dann
 * sieht es von beiden Richtungen wie ein Suchmuster aus.
 */
function countFinderLike(history: number[]): number {
  const unit = history[1];
  const core = unit > 0
    && history[2] === unit
    && history[3] === unit * 3
    && history[4] === unit
    && history[5] === unit;
  if (!core) return 0;
  return (history[0] >= unit * 4 && history[6] >= unit ? 1 : 0)
    + (history[6] >= unit * 4 && history[0] >= unit ? 1 : 0);
}

// MARK: - Ausgabe

/**
 * Der Code als ein einzelner SVG-Pfad.
 *
 * Ein Pfad und nicht tausend Rechtecke: auf dem Fernseher ist jedes
 * DOM-Element teuer, und ein Code der Fassung 4 hätte über tausend davon. Ein
 * `<path>` ist ein Knoten.
 */
export function qrSvgPath(code: QrCode): string {
  const parts: string[] = [];
  for (let row = 0; row < code.size; row += 1) {
    for (let column = 0; column < code.size; column += 1) {
      if (code.modules[row][column]) parts.push(`M${column} ${row}h1v1h-1z`);
    }
  }
  return parts.join("");
}
