import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GeoPoint } from '../src/model/GeoPoint';
import { angleDiffDeg, bearingDeg, distanceM, normalizeDeg, relativePosition } from '../src/guide/geo';

function pt(lat: number, lon: number): GeoPoint {
  const p: GeoPoint = { lat: lat, lon: lon };
  return p;
}

function near(actual: number, expected: number, tolerance: number): void {
  assert.ok(Math.abs(actual - expected) <= tolerance, `expected ${expected} ± ${tolerance}, got ${actual}`);
}

// both taken from fixtures/pois-krakow.json
const BARBAKAN = pt(50.065514, 19.941617);
const SUKIENNICE = pt(50.061667, 19.937222);

test('distance: Barbakan to Sukiennice is about 530 m', () => {
  near(distanceM(BARBAKAN, SUKIENNICE), 530, 5);
});

test('distance: one degree of latitude is about 111.2 km', () => {
  near(distanceM(pt(50, 20), pt(51, 20)), 111195, 10);
});

test('distance: same point is zero and distance is symmetric', () => {
  assert.equal(distanceM(BARBAKAN, BARBAKAN), 0);
  near(distanceM(BARBAKAN, SUKIENNICE), distanceM(SUKIENNICE, BARBAKAN), 1e-6);
});

test('bearing: north, east, south, west', () => {
  near(bearingDeg(pt(50, 20), pt(51, 20)), 0, 0.01);
  near(bearingDeg(pt(50, 20), pt(50, 20.01)), 90, 0.01);
  near(bearingDeg(pt(50, 20), pt(49, 20)), 180, 0.01);
  near(bearingDeg(pt(50, 20), pt(50, 19.99)), 270, 0.01);
});

test('normalizeDeg wraps negatives and values above 360', () => {
  assert.equal(normalizeDeg(-30), 330);
  assert.equal(normalizeDeg(370), 10);
  assert.equal(normalizeDeg(360), 0);
});

test('angleDiff crosses north correctly', () => {
  near(angleDiffDeg(350, 10), 20, 1e-9);
  near(angleDiffDeg(10, 350), -20, 1e-9);
  near(angleDiffDeg(90, 90), 0, 1e-9);
  near(angleDiffDeg(0, 270), -90, 1e-9);
});

test('relative position: point straight ahead', () => {
  const r = relativePosition(pt(50, 20), 0, pt(50.0009, 20)); // ~100 m north, walking north
  near(r.alongM, 100, 1);
  near(r.crossM, 0, 0.5);
});

test('relative position: right is positive, left is negative, behind is negative along', () => {
  const walker = pt(50, 20);
  const east = relativePosition(walker, 0, pt(50, 20.0014));   // walking north, point to the east
  const west = relativePosition(walker, 0, pt(50, 19.9986));
  const south = relativePosition(walker, 0, pt(49.9991, 20));
  assert.ok(east.crossM > 90, `east crossM ${east.crossM}`);
  near(east.alongM, 0, 1);
  assert.ok(west.crossM < -90, `west crossM ${west.crossM}`);
  assert.ok(south.alongM < -90, `south alongM ${south.alongM}`);
});

test('relative position: heading matters (walking east, the north point is on the left)', () => {
  const r = relativePosition(pt(50, 20), 90, pt(50.0009, 20));
  assert.ok(r.crossM < -90, `crossM ${r.crossM}`);
  near(r.alongM, 0, 1);
});
