// POIs near a point: live Wikipedia -> cache (fresh, then stale) -> bundled fixtures.
// Each POI carries the signals from #40 (importance, role, partOfId); see signals.js.
// Also the registry of known POIs by id, used by /v1/segment (P4) to load source text.
import { readFileSync } from 'node:fs';
import { gridCell, haversineM } from '../geo.js';
import { applySignals, importanceFromLanglinks, RULES, withDefaultSignals } from './signals.js';
import { pageToPoi } from './wikipedia.js';

export const MAX_POIS = 50;
const CELL_M = 150;   // one cache entry per ~150 m cell, fetched around the cell centre

export class PoiService {
  /**
   * @param {{
   *   wiki: import('./wikipedia.js').WikipediaClient,
   *   wikidata?: import('./wikidata.js').WikidataClient | null,
   *   areaCache: import('../cache/JsonCache.js').JsonCache,
   *   articleCache: import('../cache/JsonCache.js').JsonCache,
   *   fixturePois: object[],
   *   log?: (msg: string) => void,
   * }} deps
   */
  constructor({ wiki, wikidata = null, areaCache, articleCache, fixturePois, log = () => {} }) {
    this.wiki = wiki;
    this.wikidata = wikidata;
    this.areaCache = areaCache;
    this.articleCache = articleCache;
    this.fixturePois = fixturePois.map(withDefaultSignals);
    this.log = log;
    this.byId = new Map();
    this.#register(this.fixturePois);
    for (const key of areaCache.entries.keys()) this.#register(entryPois(areaCache.getStale(key)));
  }

  /** @returns {Promise<{ pois: object[], source: 'live'|'cache'|'fixture', warnings: string[] }>} */
  async near(lat, lon, radiusM) {
    const cell = gridCell(lat, lon, CELL_M);
    let entry = this.areaCache.get(cell.key);
    let source = 'cache';
    if (!entry) {
      try {
        entry = await this.#fetchArea(cell.lat, cell.lon);
        // a degraded result (fallback signals) is served but not kept as fresh: next request retries
        this.areaCache.set(cell.key, entry, { stale: entry.warnings.length > 0 });
        source = 'live';
      } catch (err) {
        // the message never contains the query position
        this.log(`pois: upstream failed (${err.name}: ${err.message}), falling back`);
        entry = normalizeEntry(this.areaCache.getStale(cell.key));
        if (!entry) {
          entry = { pois: this.fixturePois, warnings: [] };
          source = 'fixture';
        }
      }
    }
    entry = normalizeEntry(entry);
    this.#register(entry.pois);
    const pois = entry.pois
      .map((p) => ({ ...p, distanceM: Math.round(haversineM(lat, lon, p.lat, p.lon)) }))
      .filter((p) => p.distanceM <= radiusM)
      .sort((a, b) => a.distanceM - b.distanceM)
      .slice(0, MAX_POIS);
    return { pois, source, warnings: entry.warnings };
  }

  /**
   * Two searches around the cell centre (#40): the nearest places in a small radius, plus important
   * places (importance >= farMinImportance) in a wide one, so big sights are not crowded out by
   * dozens of town houses. Throws only when the main GeoSearch fails.
   */
  async #fetchArea(lat, lon) {
    const near = (await this.wiki.geosearch(lat, lon, RULES.nearRadiusM, RULES.nearLimit)).map(pageToPoi).filter(Boolean);
    let farIds = [];
    try {
      const nearIds = new Set(near.map((p) => pageidOf(p.id)));
      farIds = (await this.wiki.geosearchIds(lat, lon, RULES.farRadiusM, RULES.farLimit)).filter((id) => !nearIds.has(id));
    } catch (err) {
      this.log(`pois: wide search failed (${err.message})`);
    }

    let langlinks = null;
    try {
      langlinks = await this.wiki.langlinkCounts([...near.map((p) => pageidOf(p.id)), ...farIds]);
    } catch (err) {
      this.log(`pois: langlinks failed (${err.message})`);
    }

    let far = [];
    if (langlinks !== null && farIds.length > 0) {
      const important = farIds.filter((id) => importanceFromLanglinks(langlinks.get(id) ?? 0) >= RULES.farMinImportance);
      if (important.length > 0) {
        try {
          far = (await this.wiki.pages(important)).map(pageToPoi).filter(Boolean);
        } catch (err) {
          this.log(`pois: details of wide-search places failed (${err.message})`);
        }
      }
    }

    const byId = new Map();
    for (const p of [...near, ...far]) byId.set(p.id, p);
    const pois = [...byId.values()];

    let claims = null;
    if (this.wikidata) {
      try {
        claims = await this.wikidata.claims(pois.map((p) => p.wikidataId).filter(Boolean));
      } catch (err) {
        this.log(`pois: wikidata failed (${err.message})`);
      }
    }
    return applySignals(pois, { langlinks, claims });
  }

  /** POI seen in any response or in fixtures, without `distanceM`. */
  get(id) {
    return this.byId.get(id) ?? null;
  }

  /**
   * Longer source text for DEEP_DIVE. Falls back to the POI summary when Wikipedia is unreachable.
   * @returns {Promise<{ text: string, sections: {title: string|null, text: string}[], sourceUrl: string, partial: boolean } | null>}
   */
  async deepSource(id) {
    const poi = this.get(id);
    if (!poi) return null;
    const cached = this.articleCache.get(id);
    if (cached) return cached;
    const pageid = id.startsWith('plwiki:') ? id.slice('plwiki:'.length) : null;
    try {
      const article = pageid ? await this.wiki.article(pageid) : null;
      if (article?.text) {
        const value = { text: article.text, sections: article.sections, sourceUrl: article.sourceUrl ?? poi.sourceUrl, partial: false };
        this.articleCache.set(id, value);
        return value;
      }
    } catch (err) {
      this.log(`deep source ${id}: ${err.message}`);
    }
    return this.articleCache.getStale(id)
      ?? { text: poi.summary, sections: [{ title: null, text: poi.summary }], sourceUrl: poi.sourceUrl, partial: true };
  }

  #register(pois) {
    for (const p of pois ?? []) {
      const { distanceM, ...poi } = p;
      this.byId.set(poi.id, poi);
    }
  }
}

function pageidOf(id) {
  return Number.parseInt(id.split(':')[1], 10);
}

/** Cache entries written before #40 were plain arrays without signals. */
function normalizeEntry(entry) {
  if (!entry) return undefined;
  if (Array.isArray(entry)) return { pois: entry.map(withDefaultSignals), warnings: [] };
  return entry;
}

function entryPois(entry) {
  return normalizeEntry(entry)?.pois ?? [];
}

export function loadFixturePois(file) {
  try {
    const data = JSON.parse(readFileSync(file, 'utf8'));
    return (data.pois ?? data).map(({ distanceM, ...p }) => p);
  } catch (err) {
    console.warn(`pois: cannot read fixtures ${file}: ${err.message}`);
    return [];
  }
}
