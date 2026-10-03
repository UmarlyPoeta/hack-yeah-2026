// Records real MediaWiki API responses into test/fixtures/ so `npm test` runs without network.
// Usage: npm run record-fixtures   (needs internet)
import { writeFileSync } from 'node:fs';
import { JsonCache } from '../src/cache/JsonCache.js';
import { PoiService } from '../src/pois/PoiService.js';
import { WikidataClient } from '../src/pois/wikidata.js';
import { WikipediaClient } from '../src/pois/wikipedia.js';

const OUT = new URL('../test/fixtures/', import.meta.url);
const BARBAKAN = { lat: 50.06553, lon: 19.9417 };
const SUKIENNICE_PAGEID = 19010;

const responses = [];
const recordingFetch = async (url, init) => {
  const res = await fetch(url, init);
  const body = await res.json();
  responses.push({ params: Object.fromEntries(new URL(url).searchParams), body });
  return new Response(JSON.stringify(body), { status: res.status });
};

const wiki = new WikipediaClient({ apiUrl: 'https://pl.wikipedia.org/w/api.php', timeoutMs: 15000, fetch: recordingFetch });

const pages = await wiki.geosearch(BARBAKAN.lat, BARBAKAN.lon, 300);
writeFileSync(new URL('geosearch-barbakan.json', OUT), JSON.stringify(responses, null, 1));
console.log(`geosearch: ${responses.length} responses, ${pages.length} pages`);

responses.length = 0;
const article = await wiki.article(SUKIENNICE_PAGEID);
writeFileSync(new URL('article-sukiennice.json', OUT), JSON.stringify(responses, null, 1));
console.log(`article: ${article?.title}, ${article?.text.length} chars, ${article?.sections.length} sections`);

// Full /v1/pois area fetch with signals (#40) around Wawel: GeoSearch near + wide, langlinks, Wikidata.
// Stored as { key, body } pairs; tests replay them by request URL (see test/helpers.js routedFetch).
export const WAWEL = { lat: 50.0547, lon: 19.9356 };
const calls = [];
const keyedFetch = async (url, init) => {
  const res = await fetch(url, init);
  const body = await res.json();
  calls.push({ key: requestKey(url), body });
  return new Response(JSON.stringify(body), { status: res.status });
};
const svc = new PoiService({
  wiki: new WikipediaClient({ apiUrl: 'https://pl.wikipedia.org/w/api.php', timeoutMs: 15000, fetch: keyedFetch }),
  wikidata: new WikidataClient({ apiUrl: 'https://www.wikidata.org/w/api.php', timeoutMs: 15000, fetch: keyedFetch }),
  areaCache: new JsonCache({ ttlMs: 1 }),
  articleCache: new JsonCache({ ttlMs: 1 }),
  fixturePois: [],
});
const area = await svc.near(WAWEL.lat, WAWEL.lon, 600);
writeFileSync(new URL('area-wawel.json', OUT), JSON.stringify(calls.map(slim)));
console.log(`area: ${calls.length} requests, ${area.pois.length} POIs, warnings ${JSON.stringify(area.warnings)}`);

export function requestKey(url) {
  const u = new URL(url);
  const params = [...u.searchParams.entries()].sort(([a], [b]) => a.localeCompare(b));
  return `${u.host}?${new URLSearchParams(params)}`;
}

/** Keeps only what the code reads, so the recording stays small: langlink languages, P31/P361 targets. */
function slim({ key, body }) {
  for (const pg of body.query?.pages ?? []) {
    if (pg.langlinks) pg.langlinks = pg.langlinks.map((l) => ({ lang: l.lang }));
    if (pg.extract && pg.extract.length > 600) pg.extract = pg.extract.slice(0, 600);
  }
  for (const [qid, e] of Object.entries(body.entities ?? {})) {
    const claims = {};
    for (const prop of ['P31', 'P361']) {
      claims[prop] = (e.claims?.[prop] ?? []).map((s) => ({ mainsnak: { datavalue: { value: { id: s.mainsnak?.datavalue?.value?.id } } } }));
    }
    body.entities[qid] = { id: qid, claims };
  }
  return { key, body };
}
