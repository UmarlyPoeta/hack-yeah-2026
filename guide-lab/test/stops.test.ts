import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PoiRole } from '../src/model/Poi';
import { ALWAYS_IMPORTANCE, buildStops, localThreshold, MIN_IMPORTANCE } from '../src/guide/Stops';
import { demoPoisWithSignals, fixAt, poiAt } from './helpers';

test('places within 40 m become one stop led by the most important one; areas are not stops', () => {
  const pois = [poiAt('church', 0, 0, 0.9), poiAt('parish', 5, 5, 0.1), poiAt('far', 100, 0, 0.5),
    poiAt('square', 0, 10, 0.95, PoiRole.AREA)];
  const stops = buildStops(pois);
  assert.equal(stops.length, 2);
  assert.equal(stops[0].anchor.id, 'church');
  assert.deepEqual(stops[0].members.map((p) => p.id), ['church', 'parish']);
  assert.ok(stops.every((s) => s.members.every((p) => p.id !== 'square')));
});

test('partOfId joins the parent stop even when far away; a missing parent is ignored', () => {
  const gallery = poiAt('gallery', 80, 0, 0.3);
  gallery.partOfId = 'hall';
  const orphan = poiAt('orphan', 300, 0, 0.3);
  orphan.partOfId = 'nope';
  const stops = buildStops([poiAt('hall', 0, 0, 0.8), gallery, orphan]);
  assert.deepEqual(stops.map((s) => s.members.map((p) => p.id).join('+')).sort(), ['hall+gallery', 'orphan']);
});

test('demo data: Mariacki absorbs its parish, Sukiennice the gallery', () => {
  const stops = buildStops(demoPoisWithSignals());
  const mariacki = stops.find((s) => s.anchor.name.startsWith('Kościół archiprezbiterialny'));
  assert.ok(mariacki?.members.some((p) => p.name.startsWith('Parafia')));
  const sukiennice = stops.find((s) => s.anchor.name.startsWith('Sukiennice'));
  assert.ok(sukiennice?.members.some((p) => p.name.startsWith('Galeria')));
});

test('threshold is relative: a small town with modest sights still gets main stops', () => {
  const town = [poiAt('a', 0, 0, 0.3), poiAt('b', 100, 0, 0.2), poiAt('c', 200, 0, 0.1), poiAt('d', 300, 0, 0.05)];
  const thr = localThreshold(fixAt(0, 0, 0), buildStops(town));
  assert.ok(thr <= 0.3 && thr >= MIN_IMPORTANCE, `threshold ${thr}`);
  const famous = [poiAt('x', 0, 0, 0.95), poiAt('y', 100, 0, 0.9), poiAt('z', 200, 0, 0.85)];
  assert.equal(localThreshold(fixAt(0, 0, 0), buildStops(famous)), ALWAYS_IMPORTANCE);
});
