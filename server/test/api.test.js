// Contract tests: responses of /v1/health and /v1/pois match docs/CONTRACTS.md.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';
import { createApp } from '../src/http/app.js';
import { BARBAKAN, failingFetch, listen, makeService, recorded, replayFetch } from './helpers.js';

const POI_KEYS = ['distanceM', 'id', 'imageUrl', 'kind', 'lat', 'lon', 'name', 'sourceUrl', 'summary', 'wikidataId'];

function assertError(body, code) {
  assert.deepEqual(Object.keys(body), ['error']);
  assert.equal(body.error.code, code);
  assert.equal(typeof body.error.message, 'string');
}

describe('HTTP API', () => {
  let app;
  let logs;
  let svc;

  before(async () => {
    logs = [];
    svc = makeService({ fetch: replayFetch(recorded('geosearch-barbakan.json')) });
    app = await listen(createApp({ poiService: svc, log: (m) => logs.push(m) }));
  });
  after(() => app.close());

  const get = async (path, init) => {
    const res = await fetch(app.base + path, init);
    return { status: res.status, headers: res.headers, body: await res.json() };
  };

  it('GET /v1/health', async () => {
    const { status, headers, body } = await get('/v1/health');
    assert.equal(status, 200);
    assert.match(headers.get('content-type'), /application\/json; charset=utf-8/);
    assert.deepEqual(body, { ok: true, version: '0.1.0', llm: { ok: false, model: '' }, tts: { ok: false, provider: 'none' } });
  });

  it('GET /v1/pois returns Poi[] per contract', async () => {
    const { status, body } = await get(`/v1/pois?lat=${BARBAKAN.lat}&lon=${BARBAKAN.lon}&radius=300`);
    assert.equal(status, 200);
    assert.ok(['live', 'cache', 'fixture'].includes(body.source));
    assert.ok(body.pois.length > 0 && body.pois.length <= 50);
    for (const p of body.pois) {
      assert.deepEqual(Object.keys(p).sort(), POI_KEYS);
      assert.match(p.id, /^plwiki:\d+$/);
      assert.equal(typeof p.name, 'string');
      assert.equal(typeof p.summary, 'string');
      assert.equal(typeof p.lat, 'number');
      assert.equal(typeof p.lon, 'number');
      assert.ok(p.kind === null || typeof p.kind === 'string');
      assert.ok(p.wikidataId === null || /^Q\d+$/.test(p.wikidataId));
      assert.ok(p.imageUrl === null || p.imageUrl.startsWith('https://'));
      assert.ok(p.sourceUrl.startsWith('https://pl.wikipedia.org/'));
      assert.ok(Number.isInteger(p.distanceM) && p.distanceM <= 300);
    }
  });

  it('radius defaults to 300', async () => {
    const { body } = await get(`/v1/pois?lat=${BARBAKAN.lat}&lon=${BARBAKAN.lon}`);
    assert.ok(body.pois.every((p) => p.distanceM <= 300));
    assert.ok(body.pois.some((p) => p.distanceM > 150));
  });

  for (const [name, query] of [
    ['missing lat', 'lon=19.94'],
    ['missing lon', 'lat=50.06'],
    ['non-numeric lat', 'lat=abc&lon=19.94'],
    ['empty lon', 'lat=50.06&lon='],
    ['lat out of range', 'lat=91&lon=19.94'],
    ['lon out of range', 'lat=50&lon=-181'],
    ['radius too small', 'lat=50.06&lon=19.94&radius=49'],
    ['radius too big', 'lat=50.06&lon=19.94&radius=1001'],
    ['radius not a number', 'lat=50.06&lon=19.94&radius=far'],
  ]) {
    it(`400 invalid_params: ${name}`, async () => {
      const { status, body } = await get(`/v1/pois?${query}`);
      assert.equal(status, 400);
      assertError(body, 'invalid_params');
    });
  }

  it('404 not_found for unknown routes', async () => {
    const { status, body } = await get('/v2/nothing');
    assert.equal(status, 404);
    assertError(body, 'not_found');
  });

  it('405 for a wrong method, with Allow header', async () => {
    const { status, headers, body } = await get('/v1/pois', { method: 'POST' });
    assert.equal(status, 405);
    assert.equal(headers.get('allow'), 'GET');
    assertError(body, 'method_not_allowed');
  });

  it('never logs the query string (user position)', async () => {
    await get(`/v1/pois?lat=${BARBAKAN.lat}&lon=${BARBAKAN.lon}`);
    assert.ok(logs.length > 0);
    assert.ok(logs.every((l) => !l.includes(String(BARBAKAN.lat)) && !l.includes('lat=')), logs.join('\n'));
  });
});

describe('HTTP API: fallbacks and extension', () => {
  it('upstream down: 200 with source "fixture", never 5xx', async () => {
    const app = await listen(createApp({ poiService: makeService({ fetch: failingFetch() }) }));
    try {
      const res = await fetch(`${app.base}/v1/pois?lat=${BARBAKAN.lat}&lon=${BARBAKAN.lon}`);
      const body = await res.json();
      assert.equal(res.status, 200);
      assert.equal(body.source, 'fixture');
      assert.ok(body.pois.length > 0);
    } finally {
      await app.close();
    }
  });

  it('extra routes and health checks plug in (used by P4 for /v1/segment)', async () => {
    const app = await listen(createApp({
      poiService: makeService({ fetch: failingFetch() }),
      health: {
        llm: async () => ({ ok: true, model: 'bielik' }),
        tts: async () => { throw new Error('down'); },
      },
      routes: [
        { method: 'GET', path: /^\/v1\/audio\/(?<id>[\w-]+)\.mp3$/, handler: (_q, res, { params }) => res.end(params.id) },
        { method: 'POST', path: '/v1/boom', handler: () => { throw new Error('bug'); } },
      ],
    }));
    try {
      const health = await (await fetch(`${app.base}/v1/health`)).json();
      assert.deepEqual(health.llm, { ok: true, model: 'bielik' });
      assert.deepEqual(health.tts, { ok: false, provider: 'none' });
      assert.equal(await (await fetch(`${app.base}/v1/audio/abc-1.mp3`)).text(), 'abc-1');
      const boom = await fetch(`${app.base}/v1/boom`, { method: 'POST' });
      assert.equal(boom.status, 500);
      assertError(await boom.json(), 'internal');
    } finally {
      await app.close();
    }
  });
});
