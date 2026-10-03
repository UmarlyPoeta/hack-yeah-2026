import { Poi } from '../model/Poi';
import { Segment, SegmentKind, SegmentOrigin } from '../model/Segment';
import { Side } from './Itinerary';

// Narration without AI: used when the server is off, too slow, or the model output was rejected.
// Texts are Polish and written to be read aloud, so distances are words ("metrów"), not "m".
// The same templates are listed in docs/CONTRACTS.md and used by the server.

export const WORDS_PER_SECOND: number = 2.5;

// Abbreviations that end with a dot but do not end a sentence ("ul. Floriańskiej", "św. Floriana").
const ABBREVIATIONS: Set<string> = new Set<string>([
  'św', 'ul', 'pl', 'al', 'os', 'ok', 'r', 'w', 'ww', 'wg', 'im', 'tzw', 'np', 'ks', 'bp', 'abp', 'o',
  'gen', 'prof', 'dr', 'inż', 'zm', 'ur', 'nr', 'tj', 'ds', 'pw', 'płk', 'kpt', 'mjr', 'jw', 'm.in'
]);
const UPPER_START: RegExp = /^["„(«]?[A-ZĄĆĘŁŃÓŚŹŻ0-9]/;

export function countWords(text: string): number {
  const t = text.trim();
  return t.length === 0 ? 0 : t.split(/\s+/).length;
}

export function estimateDurationMs(text: string): number {
  return Math.round(countWords(text) / WORDS_PER_SECOND * 1000);
}

// "Dom Wita Stwosza w Krakowie" -> "Dom Wita Stwosza"; "Kościół X (Stare Miasto)" -> "Kościół X".
export function displayName(poi: Poi): string {
  return poi.name.replace(/\s*\([^)]*\)\s*$/, '').replace(/ w [A-ZĄĆĘŁŃÓŚŹŻ][a-ząćęłńóśźż]+$/, '');
}

// Splits on . ! ? followed by a capitalised word, unless the dot belongs to an abbreviation,
// a single-letter initial ("J. Matejki") or a Roman numeral ("XIV. "), so "św. Floriana" stays whole.
export function splitSentences(text: string): string[] {
  const words = text.replace(/\s+/g, ' ').trim().split(' ');
  const sentences: string[] = [];
  let current: string[] = [];
  for (let i = 0; i < words.length; i++) {
    const word = words[i];
    if (word.length === 0) {
      continue;
    }
    current.push(word);
    const next = i + 1 < words.length ? words[i + 1] : '';
    const last = word.charAt(word.length - 1);
    if (last !== '.' && last !== '!' && last !== '?') {
      continue;
    }
    if (next.length > 0 && !UPPER_START.test(next)) {
      continue;
    }
    if (last === '.' && isAbbreviation(word.slice(0, word.length - 1)) && next.length > 0) {
      continue;
    }
    sentences.push(current.join(' '));
    current = [];
  }
  if (current.length > 0) {
    sentences.push(current.join(' '));
  }
  return sentences;
}

function isAbbreviation(token: string): boolean {
  const bare = token.replace(/^["„(«]+/, '');
  if (ABBREVIATIONS.has(bare.toLowerCase())) {
    return true;
  }
  if (bare.length === 1) {
    return true;                              // initial: "J. Matejki"
  }
  return /^[IVXLCDM]+$/.test(bare);           // Roman numeral: "Zygmunta I. Starego"
}

// Whole sentences up to maxWords. The first sentence is always used; if it alone is too long
// it is cut at maxWords and ends with an ellipsis.
export function takeWords(text: string, maxWords: number): string {
  const sentences = splitSentences(text);
  if (sentences.length === 0) {
    return '';
  }
  const out: string[] = [];
  let words = 0;
  for (const s of sentences) {
    const n = countWords(s);
    if (out.length > 0 && words + n > maxWords) {
      break;
    }
    out.push(s);
    words += n;
  }
  if (words > maxWords) {
    return out[0].split(' ').slice(0, maxWords).join(' ').replace(/[,;:–-]+$/, '') + '…';
  }
  return out.join(' ');
}

function roundedMetres(distanceM: number): number {
  return Math.max(10, Math.round(distanceM / 10) * 10);
}

function sideWord(side: Side): string {
  return side === Side.LEFT ? 'po lewej' : (side === Side.RIGHT ? 'po prawej' : 'przed nami');
}

function joinNames(names: string[]): string {
  if (names.length <= 1) {
    return names.join('');
  }
  return names.slice(0, names.length - 1).join(', ') + ' i ' + names[names.length - 1];
}

export function welcomeText(first: Poi | null, distanceM: number): string {
  if (first === null) {
    return 'Zaczynamy spacer. Gdy będziemy mijać coś ciekawego, opowiem o tym.';
  }
  return 'Zaczynamy spacer. Pierwszy przystanek: ' + displayName(first) + ', około '
    + roundedMetres(distanceM) + ' metrów przed nami.';
}

// "Tuż obok" when the place is almost here: used e.g. when two sights follow each other closely.
export function approachText(poi: Poi, distanceM: number, side: Side): string {
  if (distanceM < 20) {
    return 'Tuż obok, ' + sideWord(side) + ': ' + displayName(poi) + '.';
  }
  return 'Za około ' + roundedMetres(distanceM) + ' metrów ' + sideWord(side) + ': ' + displayName(poi) + '.';
}

export function arrivalText(poi: Poi, maxWords: number, alsoHere: Poi[]): string {
  const extra = alsoHere.length > 0
    ? ' Obok: ' + joinNames(alsoHere.slice(0, 3).map((p: Poi) => displayName(p))) + '.'
    : '';
  return takeWords(poi.summary, Math.max(10, maxWords - countWords(extra))) + extra;
}

// Names stay in the nominative ("za nami: X"), because Polish case endings of arbitrary names
// cannot be generated reliably without a model.
export function bridgeText(from: Poi, to: Poi): string {
  return 'Idziemy dalej. Za nami: ' + displayName(from) + ', przed nami: ' + displayName(to) + '.';
}

export function deepDiveText(poi: Poi, maxWords: number): string {
  return takeWords(poi.summary, maxWords);
}

export function missedText(poi: Poi, side: Side): string {
  if (side === Side.AHEAD) {
    return 'Już za nami: ' + displayName(poi) + '.';
  }
  return (side === Side.LEFT ? 'Po lewej' : 'Po prawej') + ', już za nami: ' + displayName(poi) + '.';
}

export function segmentKey(kind: SegmentKind, poiId: string, fromPoiId: string | null): string {
  return kind + '|' + poiId + '|' + (fromPoiId !== null ? fromPoiId : '');
}

export function templateSegment(kind: SegmentKind, poi: Poi | null, fromPoiId: string | null, text: string): Segment {
  const poiId = poi !== null ? poi.id : '';
  const s: Segment = {
    id: 'tpl:' + segmentKey(kind, poiId, fromPoiId),
    kind: kind,
    poiId: poiId,
    fromPoiId: fromPoiId,
    text: text,
    claims: [],
    origin: SegmentOrigin.TEMPLATE,
    llmModel: null,
    audioUrl: null,
    durationMs: null,
    voice: null,
    sourceUrls: poi !== null ? [poi.sourceUrl] : [],
    warnings: []
  };
  return s;
}
