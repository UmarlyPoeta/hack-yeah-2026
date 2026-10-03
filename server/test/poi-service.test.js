import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { describe, it } from 'node:test';
import { JsonCache } from '../src/cache/JsonCache.js';
import { MAX_POIS } from '../src/pois/PoiService.js';
import { BARBAKAN, failingFetch, fakeClock, makeService, recorded, replayFetch } from './helpers.js';

const DAY = 24 * 3600 * 1000;
const geosearch = () => replayFetch(recorded('geosearch-barbakan.json'));

describe('PoiService.near', () => {
  it('fetches live, then serves the same grid cell from cache', async () => {
    const fetch = geosearch();
    const svc = makeService({ fetch });
    const first = await svc.near(BARBAKAN.lat, BARBAKAN.lon, 300);
    assert.equal(first.source, 'live');
    const calls = fetch.calls.length;
    const second = await svc.near(BARBAKAN.lat + 0.00001, BARBAKAN.lon, 300);
    assert.equal(second.source, 'cache');
    assert.equal(fetch.calls.length, calls, 'cache hit must not call Wikipedia');
  });

  it('returns POIs sorted by distance, within radius, at most 50, with integer distanceM', async () => {
    const svc = makeService({ fetch: geosearch() });
    const { pois } = await svc.near(BARBAKAN.lat, BARBAKAN.lon, 150);
    assert.ok(pois.length > 0 && pois.length <= MAX_POIS);
    for (let i = 1; i < pois.length; i++) assert.ok(pois[i - 1].distanceM <= pois[i].distanceM);
    assert.ok(pois.every((p) => Number.isInteger(p.distanceM) && p.distanceM <= 150));
    assert.equal(pois[0].name, 'Barbakan w Krakowie');
  });

  it('falls back to a stale cache entry when Wikipedia fails after TTL', async () => {
    const clock = fakeClock();
    const svc = makeService({ fetch: geosearch(), clock });
    await svc.near(BARBAKAN.lat, BARBAKAN.lon, 300);
    clock.t += 2 * DAY;
    svc.wiki.fetch = failingFetch();
    const res = await svc.near(BARBAKAN.lat, BARBAKAN.lon, 300);
    assert.equal(res.source, 'cache');
    assert.ok(res.pois.length > 0);
    assert.equal(svc.wiki.fetch.calls.length, 1, 'expired entry must trigger a refresh attempt');
  });

  it('falls back to bundled fixtures when Wikipedia fails and nothing is cached', async () => {
    const svc = makeService({ fetch: failingFetch() });
    const res = await svc.near(BARBAKAN.lat, BARBAKAN.lon, 300);
    assert.equal(res.source, 'fixture');
    assert.ok(res.pois.some((p) => p.name === 'Barbakan w Krakowie'));
  });

  it('falls back to fixtures on timeout', async () => {
    const svc = makeService({ fetch: failingFetch(new DOMException('timed out', 'TimeoutError')) });
    assert.equal((await svc.near(BARBAKAN.lat, BARBAKAN.lon, 300)).source, 'fixture');
  });

  it('returns an empty list, not an error, far from any fixture data', async () => {
    const svc = makeService({ fetch: failingFetch() });
    assert.deepEqual(await svc.near(52.2297, 21.0122, 300), { pois: [], source: 'fixture' });
  });
});

describe('PoiService registry and deep source', () => {
  it('knows fixture POIs and POIs seen in live responses, without distanceM', async () => {
    const svc = makeService({ fetch: geosearch(), fixturePois: [] });
    assert.equal(svc.get('plwiki:19617'), null);
    await svc.near(BARBAKAN.lat, BARBAKAN.lon, 300);
    const poi = svc.get('plwiki:19617');
    assert.equal(poi.name, 'Barbakan w Krakowie');
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
