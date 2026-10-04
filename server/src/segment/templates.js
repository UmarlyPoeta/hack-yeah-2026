// Text without AI for every segment kind (docs/CONTRACTS.md, "Szablony"; the app has the same in guide/Templates.ets).
// The server never receives the user's position, so APPROACH / MISSED / WELCOME use the forms without distance
// and side ("Tuż obok", "Minęliśmy"); the app's local templates add them.

const ABBREV = /\b(?:ul|pl|al|św|im|ok|m\.in|tzw|r|w|wł|godz|nr|ks|dr|prof|ss|oo)\.$/i;

/** Splits on . ! ? followed by a capital letter or a digit, keeping common Polish abbreviations together. */
export function sentences(text) {
  const parts = text.replace(/\s+/g, ' ').trim().split(/(?<=[.!?])\s+(?=["„(]?[A-ZĄĆĘŁŃÓŚŹŻ0-9])/u);
  const out = [];
  for (const p of parts) {
    if (out.length && ABBREV.test(out[out.length - 1])) out[out.length - 1] += ` ${p}`;
    else out.push(p);
  }
  return out.filter(Boolean);
}

/** First sentences of `text` that fit in `maxWords` (always at least one sentence, cut at the budget). */
export function leadSentences(text, maxSentences, maxWords) {
  const picked = [];
  let words = 0;
  for (const s of sentences(text).slice(0, maxSentences)) {
    const n = s.split(' ').length;
    if (picked.length && words + n > maxWords) break;
    picked.push(s);
    words += n;
  }
  const out = picked.join(' ').split(' ');
  return out.length > maxWords ? `${out.slice(0, maxWords).join(' ')}…` : out.join(' ');
}

/**
 * @param {{ kind: string, maxWords: number }} req
 * @param {{ name: string, summary: string }} poi target POI (BRIDGE: the next one)
 * @param {{ name: string } | null} [fromPoi]
 */
export function templateText(req, poi, fromPoi = null) {
  switch (req.kind) {
    case 'WELCOME':
      return `Zaczynamy spacer. Pierwszy przystanek: ${poi.name}.`;
    case 'APPROACH':
      return `Tuż przed nami: ${poi.name}.`;
    case 'ARRIVAL':
      return leadSentences(poi.summary, 3, req.maxWords);
    case 'BRIDGE':
      // names stay in the nominative ("Za nami: …"): arbitrary place names are not declined here
      return fromPoi ? `Za nami: ${fromPoi.name}. Idziemy dalej, przed nami: ${poi.name}.` : `Idziemy dalej, przed nami: ${poi.name}.`;
    case 'DEEP_DIVE':
      return leadSentences(poi.summary, 6, req.maxWords);
    case 'MISSED':
      return `Właśnie minęliśmy: ${poi.name}.`;
    default:
      throw new Error(`unknown kind ${req.kind}`);
  }
}
