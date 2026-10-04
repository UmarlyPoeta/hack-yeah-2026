// POI signals for the guide engine (#40): importance, role and partOfId.
// The rules live in poi-rules.json, shared with tools/gen_fixtures.py.
import { readFileSync } from 'node:fs';

export const RULES = JSON.parse(readFileSync(new URL('./poi-rules.json', import.meta.url), 'utf8'));

const AREA_CLASSES = new Set(Object.keys(RULES.areaClasses));
const EXCLUDED_CLASSES = new Set(Object.keys(RULES.excludedClasses));

/** log(1 + n) / log(1 + cap), clipped to 0..1, rounded to 3 decimals. n = number of language versions. */
export function importanceFromLanglinks(n) {
  const v = Math.log(1 + Math.max(0, n)) / Math.log(1 + RULES.importanceLanglinksCap);
  return round3(Math.min(1, v));
}

/** Fallback when language links are unavailable: longer intro = better known place. */
export function importanceFromSummary(summary) {
  return round3(Math.min(1, (summary ?? '').length / RULES.importanceSummaryFallbackChars));
}

/** Role and exclusion from Wikidata P31 ("instance of"). */
export function classifyByClasses(p31) {
  const classes = p31 ?? [];
  const excluded = classes.length > 0 && classes.every((c) => EXCLUDED_CLASSES.has(c));
  return { role: classes.some((c) => AREA_CLASSES.has(c)) ? 'area' : 'sight', excluded };
}

/** Fallback when Wikidata is unavailable: Polish name prefixes. */
export function classifyByName(name) {
  const n = name ?? '';
  return {
    role: RULES.areaNamePrefixes.some((p) => n.startsWith(p)) ? 'area' : 'sight',
    excluded: RULES.excludedNamePrefixes.some((p) => n.startsWith(p)),
  };
}

/**
 * Adds importance, role and partOfId to POIs and drops parishes/organisations.
 * @param {object[]} pois  Poi without the new fields
 * @param {{ langlinks: Map<number, number> | null, claims: Map<string, {p31: string[], p361: string[]}> | null }} data
 *   null = that source failed; the matching fallback is used and reported in `warnings`
 * @returns {{ pois: object[], warnings: string[] }}
 */
export function applySignals(pois, { langlinks, claims }) {
  const warnings = [];
  if (langlinks === null) warnings.push('importance_fallback');
  if (claims === null) warnings.push('wikidata_unavailable');
  const idByQid = new Map(pois.filter((p) => p.wikidataId).map((p) => [p.wikidataId, p.id]));
  const out = [];
  for (const p of pois) {
    const pageid = Number.parseInt(p.id.split(':')[1], 10);
    const importance = langlinks !== null
      ? importanceFromLanglinks(langlinks.get(pageid) ?? 0)
      : importanceFromSummary(p.summary);
    const c = claims !== null && p.wikidataId ? claims.get(p.wikidataId) : undefined;
    const cls = c ? classifyByClasses(c.p31) : classifyByName(p.name);
    if (cls.excluded) continue;
    let partOfId = null;
    if (c) {
      const target = c.p361.map((q) => idByQid.get(q)).find((id) => id && id !== p.id);
      partOfId = target ?? null;
    }
    out.push({ ...p, importance, role: cls.role, partOfId });
  }
  // a parent that was excluded or is not in this response cannot be referenced
  const ids = new Set(out.map((p) => p.id));
  for (const p of out) if (p.partOfId && !ids.has(p.partOfId)) p.partOfId = null;
  return { pois: out, warnings };
}

/** Defaults for data without the new fields (old cache entries, old fixtures). */
export function withDefaultSignals(p) {
  if (typeof p.importance === 'number' && (p.role === 'sight' || p.role === 'area') && p.partOfId !== undefined) return p;
  return {
    ...p,
    importance: typeof p.importance === 'number' ? p.importance : importanceFromSummary(p.summary),
    role: p.role === 'sight' || p.role === 'area' ? p.role : classifyByName(p.name).role,
    partOfId: p.partOfId ?? null,
  };
}

function round3(x) {
  return Math.round(x * 1000) / 1000;
}
