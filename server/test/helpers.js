import { readFileSync } from 'node:fs';
import http from 'node:http';
import { JsonCache } from '../src/cache/JsonCache.js';
import { PoiService } from '../src/pois/PoiService.js';
import { WikidataClient } from '../src/pois/wikidata.js';
import { WikipediaClient } from '../src/pois/wikipedia.js';

export const BARBAKAN = { lat: 50.06553, lon: 19.9417 };
export const WAWEL = { lat: 50.0547, lon: 19.9356 };   // same point as scripts/record-wiki-fixtures.js

export function recorded(name) {
  return JSON.parse(readFileSync(new URL(`./fixtures/${name}`, import.meta.url), 'utf8'));
}

/** fetch() that replays recorded responses in order, cycling; counts calls. */
export function replayFetch(responses) {
  let i = 0;
  const f = async (url) => {
    f.calls.push(url);
    const { body } = responses[i++ % responses.length];
    return new Response(JSON.stringify(body), { status: 200, headers: { 'Content-Type': 'application/json' } });
  };
  f.calls = [];
  return f;
}

export function failingFetch(error = new TypeError('fetch failed')) {
  const f = async (url) => {
    f.calls.push(url);
    throw error;
  };
  f.calls = [];
  return f;
}

export function fakeClock(start = 1_000_000) {
  const clock = () => clock.t;
  clock.t = start;
  return clock;
}

export function requestKey(url) {
  const u = new URL(url);
  const params = [...u.searchParams.entries()].sort(([a], [b]) => a.localeCompare(b));
  return `${u.host}?${new URLSearchParams(params)}`;
}

/**
 * fetch() that answers from a { key, body }[] recording by request URL; counts calls per host.
 * `fail` lists hosts or request kinds ('langlinks', 'wbgetentities', 'list=geosearch') that should fail.
 */
export function routedFetch(calls, { fail = [] } = {}) {
  const bodies = new Map(calls.map((c) => [c.key, c.body]));
  const f = async (url) => {
    f.calls.push(url);
    const key = requestKey(url);
    if (fail.some((x) => key.includes(x))) throw new TypeError('fetch failed');
    const body = bodies.get(key);
    if (!body) throw new Error(`unrecorded request ${key}`);
    return new Response(JSON.stringify(body), { status: 200, headers: { 'Content-Type': 'application/json' } });
  };
  f.calls = [];
  return f;
}

/** PoiService wired with in-memory caches. `fetch` is swappable through `svc.wiki.fetch`. */
export function makeService({ fetch, clock = fakeClock(), fixturePois = recorded('../../../fixtures/pois-krakow.json').pois } = {}) {
  const wiki = new WikipediaClient({ apiUrl: 'https://pl.wikipedia.org/w/api.php', timeoutMs: 1000, fetch });
  const wikidata = new WikidataClient({ apiUrl: 'https://www.wikidata.org/w/api.php', timeoutMs: 1000, fetch });
  return new PoiService({
    wiki,
    wikidata,
    areaCache: new JsonCache({ ttlMs: 24 * 3600 * 1000, now: clock }),
    articleCache: new JsonCache({ ttlMs: 24 * 3600 * 1000, now: clock }),
    fixturePois,
  });
}

/** Starts the app on a random port; returns { base, close }. */
export async function listen(handler) {
  const server = http.createServer(handler);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  return {
    base: `http://127.0.0.1:${port}`,
    close: () => new Promise((resolve) => {
      server.close(resolve);
      server.closeAllConnections();
    }),
  };
}
