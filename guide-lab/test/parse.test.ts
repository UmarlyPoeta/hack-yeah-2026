import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DEFAULT_ROUTE_ACCURACY_M, parsePois, parseRoute } from '../src/data/FixtureParser';

const FIXTURES = new URL('../../fixtures/', import.meta.url);
const poisText = readFileSync(new URL('pois-krakow.json', FIXTURES), 'utf8');
const routeText = readFileSync(new URL('demo-route-krakow.json', FIXTURES), 'utf8');

test('parsePois: real fixture loads completely', () => {
  const r = parsePois(poisText);
  assert.equal(r.error, null);
  assert.equal(r.rejected, 0);
  assert.equal(r.items.length, 77);
  const sukiennice = r.items.find((p) => p.name === 'Sukiennice w Krakowie');
  assert.ok(sukiennice);
  assert.ok(sukiennice.summary.length > 0);
  assert.ok(sukiennice.sourceUrl.startsWith('https://pl.wikipedia.org/'));
});

test('parsePois: broken entries are skipped, not fatal', () => {
  const text = JSON.stringify({
    pois: [
      { id: 'a', name: 'Ok', summary: 's', lat: 50, lon: 20, sourceUrl: 'u' },
      { id: 'b', name: 'No coords', summary: 's', sourceUrl: 'u' },
      { id: 'c', name: 'Bad lat', summary: 's', lat: 123, lon: 20, sourceUrl: 'u' },
      { id: 'a', name: 'Duplicate id', summary: 's', lat: 50, lon: 20, sourceUrl: 'u' },
      null,
      'not an object'
    ]
  });
  const r = parsePois(text);
  assert.equal(r.items.length, 1);
  assert.equal(r.rejected, 5);
  assert.equal(r.items[0].kind, null);
  assert.equal(r.items[0].imageUrl, null);
});

test('parsePois: invalid file reports an error instead of throwing', () => {
  assert.equal(parsePois('{not json').error, 'invalid JSON');
  assert.equal(parsePois('{"other": 1}').error, 'missing "pois" array');
});

test('parseRoute: real fixture converts seconds to milliseconds', () => {
  const r = parseRoute(routeText);
  assert.equal(r.error, null);
  assert.equal(r.rejected, 0);
  assert.equal(r.items.length, 180);
  assert.equal(r.items[0].t, 0);
  assert.equal(r.items[0].accuracyM, DEFAULT_ROUTE_ACCURACY_M);
  for (let i = 1; i < r.items.length; i++) {
    assert.ok(r.items[i].t > r.items[i - 1].t, `time not increasing at ${i}`);
  }
  // 1457 m at 1.3 m/s is about 18.7 minutes
  const last = r.items[r.items.length - 1];
  assert.ok(last.t > 18 * 60 * 1000 && last.t < 19.5 * 60 * 1000, `walk duration ${last.t} ms`);
});

test('parseRoute: points going back in time are rejected', () => {
  const r = parseRoute(JSON.stringify([
    { lat: 50, lon: 20, t: 0 },
    { lat: 50, lon: 20, t: 5 },
    { lat: 50, lon: 20, t: 3 },
    { lat: 50, lon: 20, t: 5 },
    { lat: 50, lon: 20 }
  ]));
  assert.equal(r.items.length, 2);
  assert.equal(r.rejected, 3);
  assert.equal(parseRoute('{}').error, 'route must be a JSON array');
});
