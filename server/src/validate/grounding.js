// Grounding validator for LLM segments (#18).
// - Numbers: every number in the narration must appear in the source (strict: dates and sizes are what a
//   small model makes up most often, e.g. "34 metry" for a gate whose article has no height).
// - Quotes: a claim's quote must match a passage of the source: at least QUOTE_MIN_MATCH of its words, in
//   order (Bielik often adds a period, joins two sentences or changes one ending). Bad claims are dropped;
//   the segment is rejected when more claims are bad than good.

/** Lowercase, one kind of quote and dash, single spaces: so typography alone never fails a quote. */
export function normalize(s) {
  return s
    .normalize('NFC')
    .toLowerCase()
    .replace(/[„”“"«»‚‘’']/g, '"')
    .replace(/[‐‑‒–—―]/g, '-')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Digit groups in the text: "1907–1908" -> ["1907", "1908"], "1 500" -> ["1500"]. */
export function numbersIn(s) {
  return (s.replace(/(\d)[\s ](?=\d{3}\b)/g, '$1').match(/\d+/g) ?? []);
}

export const QUOTE_MIN_MATCH = 0.8;
const QUOTE_MIN_WORDS = 3;

export function words(s) {
  return normalize(s).split(/[^\p{L}\p{N}]+/u).filter(Boolean);
}

/** Longest common subsequence length of two word arrays. */
function lcs(a, b) {
  let prev = new Array(b.length + 1).fill(0);
  for (const x of a) {
    const cur = [0];
    for (let j = 0; j < b.length; j++) cur.push(x === b[j] ? prev[j] + 1 : Math.max(prev[j + 1], cur[j]));
    prev = cur;
  }
  return prev[b.length];
}

/** True if some window of the source contains >= QUOTE_MIN_MATCH of the quote's words in order. */
export function quoteInSource(quote, sourceWords) {
  const q = words(quote);
  if (q.length < QUOTE_MIN_WORDS) return false;
  const need = Math.ceil(q.length * QUOTE_MIN_MATCH);
  const win = q.length + 4;
  const first = new Set(q.slice(0, q.length - need + 1));
  for (let i = 0; i < sourceWords.length; i++) {
    if (!first.has(sourceWords[i])) continue;
    if (lcs(q, sourceWords.slice(i, i + win)) >= need) return true;
  }
  return false;
}

export function countWords(s) {
  return s.trim().split(/\s+/).filter(Boolean).length;
}

/**
 * @param {{ text?: unknown, claims?: unknown }} result parsed LLM JSON, text already cleaned
 * @param {string} source all source text the prompt was given
 * @param {{ maxWords: number, minClaims?: number }} opts
 * @returns {{ ok: boolean, problems: string[], claims: {text: string, quote: string}[] }} claims = the grounded ones
 */
export function validateSegment(result, source, { maxWords, minClaims = 1 }) {
  const problems = [];
  const text = typeof result?.text === 'string' ? result.text.trim() : '';
  const claims = Array.isArray(result?.claims) ? result.claims : null;
  if (!text) problems.push('empty_text');
  if (!claims) problems.push('no_claims_array');
  if (problems.length) return { ok: false, problems, claims: [] };

  const srcWords = words(source);
  const srcNumbers = new Set(numbersIn(source));

  const good = [];
  const bad = [];
  for (const c of claims) {
    const quote = typeof c?.quote === 'string' ? c.quote : '';
    if (quote && quoteInSource(quote, srcWords)) good.push({ text: String(c.text ?? ''), quote });
    else bad.push(quote.slice(0, 80));
  }
  if (good.length < minClaims || bad.length > good.length) {
    for (const q of bad) problems.push(`quote_not_in_source: ${q}`);
    if (good.length < minClaims && bad.length === 0) problems.push('too_few_claims');
  }
  for (const n of new Set(numbersIn(text))) {
    if (!srcNumbers.has(n)) problems.push(`number_not_in_source: ${n}`);
  }
  if (countWords(text) > Math.ceil(maxWords * 1.5)) problems.push('too_long');
  return { ok: problems.length === 0, problems, claims: good };
}

/** Text for TTS: no Markdown emphasis, headings or list markers, single spaces. */
export function cleanText(s) {
  return s
    .replace(/[*_]{1,3}([^*_]+)[*_]{1,3}/g, '$1')
    .replace(/^\s*(#{1,6}\s+|[-•*]\s+|\d+[.)]\s+)/gm, '')
    .replace(/\s+/g, ' ')
    .trim();
}
