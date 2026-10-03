// POIs near a point: live Wikipedia -> cache (fresh, then stale) -> bundled fixtures.
// Also the registry of known POIs by id, used by /v1/segment (P4) to load source text.
import { readFileSync } from 'node:fs';
import { gridCell, haversineM } from '../geo.js';
import { pageToPoi } from './wikipedia.js';

export const MAX_POIS = 50;
const CELL_M = 100;
const CELL_MARGIN_M = 100;   // fetch a bit wider than asked, so one cache entry serves the whole cell

export class PoiService {
  /**
   * @param {{
   *   wiki: import('./wikipedia.js').WikipediaClient,
   *   areaCache: import('../cache/JsonCache.js').JsonCache,
   *   articleCache: import('../cache/JsonCache.js').JsonCache,
   *   fixturePois: object[],
   *   log?: (msg: string) => void,
   * }} deps
   */
  constructor({ wiki, areaCache, articleCache, fixturePois, log = () => {} }) {
    this.wiki = wiki;
    this.areaCache = areaCache;
    this.articleCache = articleCache;
    this.fixturePois = fixturePois;
    this.log = log;
    this.byId = new Map();
    this.#register(fixturePois);
    for (const key of areaCache.entries.keys()) this.#register(areaCache.getStale(key));
  }

  /** @returns {Promise<{ pois: object[], source: 'live'|'cache'|'fixture' }>} */
  async near(lat, lon, radiusM) {
    const cell = gridCell(lat, lon, CELL_M);
    const key = `${cell.key}:${radiusM}`;
    let candidates = this.areaCache.get(key);
    let source = 'cache';
    if (!candidates) {
      try {
        const pages = await this.wiki.geosearch(cell.lat, cell.lon, radiusM + CELL_MARGIN_M);
        candidates = pages.map(pageToPoi).filter(Boolean);
        this.areaCache.set(key, candidates);
        source = 'live';
      } catch (err) {
        // the message never contains the query position
        this.log(`pois: upstream failed (${err.name}: ${err.message}), falling back`);
        candidates = this.areaCache.getStale(key);
        if (!candidates) {
          candidates = this.fixturePois;
          source = 'fixture';
        }
      }
    }
    this.#register(candidates);
    const pois = candidates
      .map((p) => ({ ...p, distanceM: Math.round(haversineM(lat, lon, p.lat, p.lon)) }))
      .filter((p) => p.distanceM <= radiusM)
      .sort((a, b) => a.distanceM - b.distanceM)
      .slice(0, MAX_POIS);
    return { pois, source };
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

export function loadFixturePois(file) {
  try {
    const data = JSON.parse(readFileSync(file, 'utf8'));
    return (data.pois ?? data).map(({ distanceM, ...p }) => p);
  } catch (err) {
    console.warn(`pois: cannot read fixtures ${file}: ${err.message}`);
    return [];
  }
}
