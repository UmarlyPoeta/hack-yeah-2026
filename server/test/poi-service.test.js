import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { describe, it } from 'node:test';
import { JsonCache } from '../src/cache/JsonCache.js';
import { MAX_POIS } from '../src/pois/PoiService.js';
import { BARBAKAN, failingFetch, fakeClock, makeService, recorded, replayFetch, routedFetch, WAWEL } from './helpers.js';

const DAY = 24 * 3600 * 1000;
const area = (opts) => routedFetch(recorded('area-wawel.json'), opts);
const byName = (pois, prefix) => pois.find((p) => p.name.startsWith(prefix));

describe('PoiService.near', () => {
  it('fetches live, then serves the same grid cell from cache', async () => {
    const fetch = area();
    const svc = makeService({ fetch });
    const first = await svc.near(WAWEL.lat, WAWEL.lon, 300);
    assert.equal(first.source, 'live');
    assert.deepEqual(first.warnings, []);
    const calls = fetch.calls.length;
    const second = await svc.near(WAWEL.lat + 0.00001, WAWEL.lon, 300);
    assert.equal(second.source, 'cache');
    assert.equal(fetch.calls.length, calls, 'cache hit must not call Wikipedia or Wikidata');
  });

  it('returns POIs sorted by distance, within radius, at most 50, with integer distanceM', async () => {
    const svc = makeService({ fetch: area() });
    const { pois } = await svc.near(WAWEL.lat, WAWEL.lon, 150);
    assert.ok(pois.length > 0 && pois.length <= MAX_POIS);
    for (let i = 1; i < pois.length; i++) assert.ok(pois[i - 1].distanceM <= pois[i].distanceM);
    assert.ok(pois.every((p) => Number.isInteger(p.distanceM) && p.distanceM <= 150));
  });

  it('finds the big sights: Wawel castle and the cathedral, with high importance (#40)', async () => {
    const { pois } = await makeService({ fetch: area() }).near(WAWEL.lat, WAWEL.lon, 600);
    const castle = pois.find((p) => p.name === 'Zamek Królewski na Wawelu');
    const cathedral = byName(pois, 'Bazylika Archikatedralna');
    assert.ok(castle && cathedral, 'castle and cathedral must be in the response');
    assert.ok(castle.importance >= 0.6 && cathedral.importance >= 0.6);
    assert.ok(pois.every((p) => p.importance >= 0 && p.importance <= 1));
  });

  it('wide search keeps only important places beyond the near radius', async () => {
    const { pois } = await makeService({ fetch: area() }).near(WAWEL.lat, WAWEL.lon, 1000);
    // everything further than the near search (150 m from the cell centre + cell size) came from the wide search
    const far = pois.filter((p) => p.distanceM > 300);
    assert.ok(far.length > 0);
    assert.ok(far.every((p) => p.importance >= 0.6), far.map((p) => `${p.name} ${p.importance}`).join(', '));
  });

  it('marks parts of a bigger place with partOfId pointing into the same response', async () => {
    const { pois } = await makeService({ fetch: area() }).near(WAWEL.lat, WAWEL.lon, 600);
    const ids = new Set(pois.map((p) => p.id));
    const parts = pois.filter((p) => p.partOfId !== null);
    assert.ok(parts.length > 0);
    assert.ok(parts.every((p) => ids.has(p.partOfId) && p.partOfId !== p.id));
    assert.ok(pois.every((p) => p.role === 'sight' || p.role === 'area'));
  });

  it('Wikidata down: role from name prefixes, no partOfId, warning, not cached as fresh', async () => {
    const fetch = area({ fail: ['www.wikidata.org'] });
    const svc = makeService({ fetch });
    const res = await svc.near(WAWEL.lat, WAWEL.lon, 600);
    assert.equal(res.source, 'live');
    assert.deepEqual(res.warnings, ['wikidata_unavailable']);
    assert.ok(res.pois.every((p) => p.partOfId === null));
    assert.ok(res.pois.length > 0);
    const calls = fetch.calls.length;
    await svc.near(WAWEL.lat, WAWEL.lon, 600);
    assert.ok(fetch.calls.length > calls, 'a degraded result must be refetched next time');
  });

  it('langlinks down: importance from summary length, warning', async () => {
    const res = await makeService({ fetch: area({ fail: ['prop=langlinks'] }) }).near(WAWEL.lat, WAWEL.lon, 600);
    // without langlinks the wide search is skipped, so the Wikidata batch differs from the recording too
    assert.ok(res.warnings.includes('importance_fallback'));
    for (const p of res.pois) assert.equal(p.importance, Math.min(1, Math.round(p.summary.length / 2000 * 1000) / 1000));
  });

  it('falls back to a stale cache entry when Wikipedia fails after TTL', async () => {
    const clock = fakeClock();
    const svc = makeService({ fetch: area(), clock });
    await svc.near(WAWEL.lat, WAWEL.lon, 300);
    clock.t += 2 * DAY;
    svc.wiki.fetch = failingFetch();
    const res = await svc.near(WAWEL.lat, WAWEL.lon, 300);
    assert.equal(res.source, 'cache');
    assert.ok(res.pois.length > 0 && res.pois.every((p) => typeof p.importance === 'number'));
    assert.equal(svc.wiki.fetch.calls.length, 1, 'expired entry must trigger a refresh attempt');
  });

  it('reads cache entries written before #40 (plain arrays) and fills the signals', async () => {
    const svc = makeService({ fetch: failingFetch() });
    const old = recorded('../../../fixtures/pois-krakow.json').pois.slice(0, 3).map(({ importance, role, partOfId, ...p }) => p);
    const { gridCell } = await import('../src/geo.js');
    svc.areaCache.set(gridCell(BARBAKAN.lat, BARBAKAN.lon, 150).key, old);
    const res = await svc.near(BARBAKAN.lat, BARBAKAN.lon, 1000);
    assert.equal(res.source, 'cache');
    assert.ok(res.pois.every((p) => typeof p.importance === 'number' && p.role && p.partOfId !== undefined));
  });

  it('falls back to bundled fixtures when Wikipedia fails and nothing is cached', async () => {
    const svc = makeService({ fetch: failingFetch() });
    const res = await svc.near(BARBAKAN.lat, BARBAKAN.lon, 300);
    assert.equal(res.source, 'fixture');
    assert.ok(res.pois.some((p) => p.name === 'Barbakan w Krakowie'));
    assert.ok(res.pois.every((p) => typeof p.importance === 'number' && (p.role === 'sight' || p.role === 'area')));
  });

  it('falls back to fixtures on timeout', async () => {
    const svc = makeService({ fetch: failingFetch(new DOMException('timed out', 'TimeoutError')) });
    assert.equal((await svc.near(BARBAKAN.lat, BARBAKAN.lon, 300)).source, 'fixture');
  });

  it('returns an empty list, not an error, far from any fixture data', async () => {
    const svc = makeService({ fetch: failingFetch() });
    assert.deepEqual(await svc.near(52.2297, 21.0122, 300), { pois: [], source: 'fixture', warnings: [] });
  });
});

describe('PoiService registry and deep source', () => {
  it('knows fixture POIs and POIs seen in live responses, without distanceM', async () => {
    const svc = makeService({ fetch: area(), fixturePois: [] });
    const { pois } = await svc.near(WAWEL.lat, WAWEL.lon, 600);
    const castle = pois.find((p) => p.name === 'Zamek Królewski na Wawelu');
    const poi = svc.get(castle.id);
    assert.equal(poi.name, castle.name);
    assert.equal('distanceM' in poi, false);
  });

  it('loads the full article once and caches it', async () => {
    const fetch = replayFetch(recorded('article-sukiennice.json'));
    const svc = makeService({ fetch });
    const deep = await svc.deepSource('plwiki:19010');
    assert.equal(deep.partial, false);
    assert.ok(deep.text.length > svc.get('plwiki:19010').summary.length);
    await svc.deepSource('plwiki:19010');
    assert.equal(fetch.calls.length, 1);
  });

  it('falls back to the summary when Wikipedia is down; null for unknown POI', async () => {
    const svc = makeService({ fetch: failingFetch() });
    const deep = await svc.deepSource('plwiki:19010');
    assert.equal(deep.partial, true);
    assert.equal(deep.text, svc.get('plwiki:19010').summary);
    assert.equal(await svc.deepSource('plwiki:999999999'), null);
  });
});

describe('JsonCache', () => {
  it('persists entries to disk and expires them by TTL', () => {
    const dir = mkdtempSync(path.join(os.tmpdir(), 'spacer-cache-'));
    try {
      const file = path.join(dir, 'c.json');
      const clock = fakeClock();
      new JsonCache({ file, ttlMs: 1000, now: clock }).set('k', [1, 2]);
      const reopened = new JsonCache({ file, ttlMs: 1000, now: clock });
      assert.deepEqual(reopened.get('k'), [1, 2]);
      clock.t += 1001;
      assert.equal(reopened.get('k'), undefined);
      assert.deepEqual(reopened.getStale('k'), [1, 2]);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('starts empty on a corrupt file', () => {
    const dir = mkdtempSync(path.join(os.tmpdir(), 'spacer-cache-'));
    try {
      const file = path.join(dir, 'c.json');
      writeFileSync(file, '{not json');
      assert.equal(new JsonCache({ file, ttlMs: 1000 }).get('k'), undefined);
      assert.equal(new JsonCache({ file: path.join(dir, 'missing', 'x.json'), ttlMs: 1000 }).get('k'), undefined);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
