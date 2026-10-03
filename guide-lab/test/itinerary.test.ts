import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GeoFix } from '../src/model/GeoPoint';
import { Poi } from '../src/model/Poi';
import { distanceM } from '../src/guide/geo';
import { MotionTracker } from '../src/guide/MotionTracker';
import { Itinerary, ItineraryView, Side } from '../src/guide/Itinerary';
import { demoPois, demoRoute, fixAt, poiAt, withNoise } from './helpers';

// Runs a walk and returns the ids that became `next`, in order, without consecutive repeats.
function nextSequence(route: GeoFix[], pois: Poi[]): string[] {
  const m = new MotionTracker();
  const it = new Itinerary(pois);
  const out: string[] = [];
  for (const f of route) {
    const v = it.update(m.update(f));
    const id = v.next !== null ? v.next.poi.id : '-';
    if (out[out.length - 1] !== id) {
      out.push(id);
    }
  }
  return out.filter((id: string) => id !== '-');
}

interface Stint { id: string; fromS: number; toS: number; passedWhenLeft: boolean; }

// Like nextSequence, but with how long each place stayed the target.
function nextStints(route: GeoFix[], pois: Poi[]): Stint[] {
  const m = new MotionTracker();
  const it = new Itinerary(pois);
  const out: Stint[] = [];
  for (const f of route) {
    const v = it.update(m.update(f));
    const id = v.next !== null ? v.next.poi.id : '-';
    const tS = f.t / 1000;
    if (out.length > 0 && out[out.length - 1].id === id) {
      out[out.length - 1].toS = tS;
    } else {
      if (out.length > 0) {
        out[out.length - 1].passedWhenLeft = v.passedIds.includes(out[out.length - 1].id);
      }
      const s: Stint = { id: id, fromS: tS, toS: tS, passedWhenLeft: false };
      out.push(s);
    }
  }
  return out;
}

function walk(route: GeoFix[], pois: Poi[]): ItineraryView {
  const m = new MotionTracker();
  const it = new Itinerary(pois);
  let v: ItineraryView = it.update(m.snapshot());
  for (const f of route) {
    v = it.update(m.update(f));
  }
  return v;
}

function idOf(pois: Poi[], namePrefix: string): string {
  const p = pois.find((q: Poi) => q.name.startsWith(namePrefix));
  assert.ok(p !== undefined, `no POI ${namePrefix}`);
  return p.id;
}

// Index of the route point closest to a place: its position along the walk.
function routeIndex(route: GeoFix[], poi: Poi): number {
  let best = 0;
  for (let i = 1; i < route.length; i++) {
    if (distanceM(route[i], poi) < distanceM(route[best], poi)) {
      best = i;
    }
  }
  return best;
}

test('demo route: key sights become the target in walking order', () => {
  const pois = demoPois();
  const seq = nextSequence(demoRoute(), pois);
  const order = ['Barbakan', 'Brama Floriańska', 'Kościół archiprezbiterialny Wniebowzięcia', 'Kościół św. Piotra']
    .map((name: string) => seq.indexOf(idOf(pois, name)));
  for (let i = 0; i < order.length; i++) {
    assert.ok(order[i] >= 0, `sight ${i} never became next`);
    if (i > 0) {
      assert.ok(order[i] > order[i - 1], `sight ${i} out of order: ${order}`);
    }
  }
});

test('demo route: places are passed in the order they lie along the route', () => {
  const pois = demoPois();
  const route = demoRoute();
  const view = walk(route, pois);
  assert.ok(view.passedIds.length > 30, `only ${view.passedIds.length} passed`);
  const byId = new Map<string, Poi>(pois.map((p: Poi) => [p.id, p] as [string, Poi]));
  // Areas (a square, a street, the walls) are passed somewhere else than their centre point.
  // Filtering them out of the data is still to be agreed with P3, so they are skipped here.
  const AREAS = ['Rynek Główny', 'Stare Miasto', 'Ulica ', 'Mury miejskie', 'Planty'];
  let prev = -1;
  for (const id of view.passedIds) {
    const poi = byId.get(id) as Poi;
    if (AREAS.some((a: string) => poi.name.startsWith(a))) {
      continue;
    }
    const idx = routeIndex(route, poi);
    // places next to the same stretch can be passed in either order: allow ~5 route points (40 m)
    assert.ok(idx >= prev - 5, `${poi.name} at route point ${idx} passed after point ${prev}`);
    prev = Math.max(prev, idx);
  }
});

test('GPS noise does not make the target flicker back and forth', () => {
  // Flicker = A -> B -> A where B stopped being the target without being passed. Going back to A is
  // fine when B was a nearer place that got passed in between.
  const pois = demoPois();
  const clean = nextStints(demoRoute(), pois).length;
  for (const amplitude of [0, 5, 8]) {
    for (let seed = 1; seed <= 5; seed++) {
      const st = nextStints(withNoise(demoRoute(), amplitude, seed), pois);
      for (let i = 2; i < st.length; i++) {
        const flicker = st[i].id === st[i - 2].id && !st[i - 1].passedWhenLeft;
        assert.ok(!flicker, `±${amplitude} m seed ${seed}: flicker at ${st[i].fromS} s`);
      }
      assert.ok(st.length <= clean * 1.2, `±${amplitude} m seed ${seed}: ${st.length} changes vs ${clean} without noise`);
    }
  }
});

test('GPS noise: the big sights are still visited, never missed', () => {
  // ARRIVAL is triggered by distance, not by `next`, so what matters is that they are passed close by.
  const pois = demoPois();
  const must = ['Brama Floriańska', 'Kościół archiprezbiterialny Wniebowzięcia', 'Kościół św. Piotra']
    .map((name: string) => idOf(pois, name));
  for (let seed = 1; seed <= 5; seed++) {
    const view = walk(withNoise(demoRoute(), 5, seed), pois);
    for (const id of must) {
      assert.ok(view.passedIds.includes(id) && !view.missedIds.includes(id), `seed ${seed}: ${id} not visited`);
    }
  }
});

test('sides, passing and missing on a straight walk north', () => {
  const pois = [poiAt('right', 100, 30), poiAt('left', 150, -30), poiAt('far-side', 120, 90), poiAt('visited', 50, 10)];
  const walkNorth: GeoFix[] = [];
  for (let k = 0; k <= 20; k++) {
    walkNorth.push(fixAt(k * 4, 0, k * 3));          // 4 m every 3 s
  }
  const m = new MotionTracker();
  const it = new Itinerary(pois);
  let v: ItineraryView = it.update(m.snapshot());
  for (const f of walkNorth) {
    v = it.update(m.update(f));
  }
  // now at 80 m north
  const right = v.upcoming.find((u) => u.poi.id === 'right');
  const left = v.upcoming.find((u) => u.poi.id === 'left');
  assert.equal(right?.side, Side.RIGHT);
  assert.equal(left?.side, Side.LEFT);
  assert.ok(right !== undefined && left !== undefined && right.alongM < left.alongM, 'sorted by along');
  assert.ok(v.upcoming.every((u) => u.poi.id !== 'far-side'), 'outside the 60 m corridor');
  assert.ok(v.passedIds.includes('visited'), 'visited place passed');
  assert.ok(!v.missedIds.includes('visited'), 'came within 10 m, so not missed');
  for (let k = 21; k <= 60; k++) {
    v = it.update(m.update(fixAt(k * 4, 0, k * 3)));   // continue to 240 m north
  }
  // ordered by how far north they are: 50, 100, 120, 150 m
  assert.deepEqual(v.passedIds, ['visited', 'right', 'far-side', 'left']);
  assert.deepEqual(v.missedIds, ['far-side']);   // right and left were 30 m away: visited
});

test('without a heading only places closer than 40 m are ahead', () => {
  const it = new Itinerary([poiAt('near', 20, 0), poiAt('far', 100, 0)]);
  const m = new MotionTracker();
  const v = it.update(m.update(fixAt(0, 0, 0)));
  assert.deepEqual(v.upcoming.map((u) => u.poi.id), ['near']);
  assert.equal(v.next?.poi.id, 'near');
  assert.equal(v.next?.side, Side.AHEAD);
});

test('standing still gives a finite ETA (minimum pace 0.8 m/s)', () => {
  const it = new Itinerary([poiAt('a', 30, 0)]);
  const m = new MotionTracker();
  const v = it.update(m.update(fixAt(0, 0, 0)));
  assert.ok(v.next !== null && Math.abs(v.next.etaS - 30 / 0.8) < 1, `eta ${v.next?.etaS}`);
});

test('the target only switches when another place is at least 15 s sooner', () => {
  // walking north; A straight ahead at 100 m, B appears slightly sooner, C much sooner
  const m = new MotionTracker();
  for (let k = 0; k <= 8; k++) {             // 32 m: enough for a heading
    m.update(fixAt(k * 4, 0, k * 3));
  }
  const pois = [poiAt('A', 132, 0)];
  const it = new Itinerary(pois);
  assert.equal(it.update(m.snapshot()).next?.poi.id, 'A');
  pois.push(poiAt('B', 122, 5));            // ~7 s sooner: keep A
  assert.equal(it.update(m.snapshot()).next?.poi.id, 'A');
  pois.push(poiAt('C', 62, 5));             // ~70 s sooner: switch
  assert.equal(it.update(m.snapshot()).next?.poi.id, 'C');
});
