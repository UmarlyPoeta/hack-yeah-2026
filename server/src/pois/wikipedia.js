// MediaWiki API client for pl.wikipedia.org: GeoSearch for POIs, full article text for deep dives.
// Not Wikidata SPARQL: during the hackathon it was rate-limited to 1 request/minute.

export const USER_AGENT = 'SpacerZHistoria/0.1 (https://github.com/UmarlyPoeta/hack-yeah-2026; HackYeah 2026)';

// coordinate types that describe areas, not places you can stand next to
const AREA_TYPES = new Set(['city', 'adm1st', 'adm2nd', 'adm3rd', 'country', 'region', 'isle', 'waterbody']);
const MAX_DIM_M = 5000;
const MAX_CONTINUATIONS = 4;
const DEEP_MAX_CHARS = 8000;
const SKIP_SECTIONS = new Set(['Przypisy', 'Bibliografia', 'Linki zewnętrzne', 'Zobacz też', 'Uwagi']);

export class WikipediaClient {
  /** @param {{ apiUrl: string, timeoutMs: number, fetch?: typeof fetch }} opts */
  constructor({ apiUrl, timeoutMs, fetch: fetchImpl = globalThis.fetch }) {
    this.apiUrl = apiUrl;
    this.timeoutMs = timeoutMs;
    this.fetch = fetchImpl;
  }

  /** Pages with coordinates within `radiusM` of the point, extracts merged across continuations. */
  async geosearch(lat, lon, radiusM) {
    const params = {
      action: 'query', format: 'json', formatversion: '2',
      generator: 'geosearch', ggscoord: `${lat}|${lon}`, ggsradius: String(Math.min(radiusM, 10000)), ggslimit: '50',
      prop: 'coordinates|pageprops|extracts|pageimages|info',
      coprop: 'type|dim', colimit: 'max', ppprop: 'wikibase_item',
      exintro: '1', explaintext: '1', exlimit: 'max',
      piprop: 'thumbnail', pithumbsize: '640', pilimit: 'max', inprop: 'url',
    };
    const pages = new Map();
    let cont = {};
    for (let i = 0; i < MAX_CONTINUATIONS; i++) {
      const data = await this.#get({ ...params, ...cont });
      for (const p of data.query?.pages ?? []) pages.set(p.pageid, { ...pages.get(p.pageid), ...stripUndefined(p) });
      if (!data.continue) break;
      cont = data.continue;
    }
    return [...pages.values()];
  }

  /** Longer article text for DEEP_DIVE: sections without references, trimmed to ~8k chars. */
  async article(pageid) {
    const data = await this.#get({
      action: 'query', format: 'json', formatversion: '2', pageids: String(pageid),
      prop: 'extracts|info', explaintext: '1', exsectionformat: 'wiki', inprop: 'url',
    });
    const page = data.query?.pages?.[0];
    if (!page || page.missing || !page.extract) return null;
    const sections = splitSections(page.extract);
    return { pageid: page.pageid, title: page.title, sourceUrl: page.fullurl, sections, text: joinSections(sections, DEEP_MAX_CHARS) };
  }

  async #get(params) {
    const url = `${this.apiUrl}?${new URLSearchParams(params)}`;
    const res = await this.fetch(url, {
      headers: { 'User-Agent': USER_AGENT, 'Api-User-Agent': USER_AGENT },
      signal: AbortSignal.timeout(this.timeoutMs),
    });
    if (!res.ok) throw new Error(`wikipedia http ${res.status}`);
    const data = await res.json();
    if (data.error) throw new Error(`wikipedia api ${data.error.code}`);
    return data;
  }
}

/** Wikipedia page -> Poi (docs/CONTRACTS.md) or null when it is an area or has no text. */
export function pageToPoi(page) {
  const coords = page.coordinates ?? [];
  const coord = coords.find((c) => c.primary) ?? coords[0];
  if (!coord || typeof coord.lat !== 'number') return null;
  const dim = Number.parseInt(String(coord.dim ?? '0'), 10);   // API returns an int or a string like "1000"
  if (AREA_TYPES.has(coord.type) || dim >= MAX_DIM_M) return null;
  const summary = (page.extract ?? '').trim();
  if (!summary) return null;
  return {
    id: `plwiki:${page.pageid}`,
    name: page.title,
    summary,
    lat: round6(coord.lat),
    lon: round6(coord.lon),
    kind: coord.type ?? null,
    wikidataId: page.pageprops?.wikibase_item ?? null,
    imageUrl: page.thumbnail?.source ?? null,
    sourceUrl: page.fullurl ?? `https://pl.wikipedia.org/?curid=${page.pageid}`,
  };
}

export function splitSections(extract) {
  const sections = [];
  let current = { title: null, text: '' };
  for (const line of extract.split('\n')) {
    const m = /^(=+)\s*(.+?)\s*\1$/.exec(line.trim());
    if (m) {
      sections.push(current);
      current = { title: m[2], text: '' };
    } else {
      current.text += `${line}\n`;
    }
  }
  sections.push(current);
  return sections
    .map((s) => ({ title: s.title, text: s.text.trim() }))
    .filter((s) => s.text && !SKIP_SECTIONS.has(s.title));
}

function joinSections(sections, maxChars) {
  let out = '';
  for (const s of sections) {
    const block = s.title ? `${s.title}\n${s.text}` : s.text;
    const next = out ? `${out}\n\n${block}` : block;
    if (next.length > maxChars) {
      if (!out) return cutAtSentence(block, maxChars);
      break;
    }
    out = next;
  }
  return out;
}

function cutAtSentence(text, maxChars) {
  const cut = text.slice(0, maxChars);
  const end = cut.lastIndexOf('. ');
  return end > maxChars / 2 ? cut.slice(0, end + 1) : cut;
}

function stripUndefined(obj) {
  return Object.fromEntries(Object.entries(obj).filter(([, v]) => v !== undefined));
}

function round6(x) {
  return Math.round(x * 1e6) / 1e6;
}
