import { readFileSync } from 'node:fs';
import { GuideDirector, GuideEvents } from '../src/guide/GuideDirector';
import { GuideAction, GuideActionKind } from '../src/guide/NarrationPlanner';
import { GeoFix } from '../src/model/GeoPoint';
import { Poi, PoiRole } from '../src/model/Poi';
import { parsePois, parseRoute } from '../src/data/FixtureParser';

const FIXTURES = new URL('../../fixtures/', import.meta.url);

export function demoPois(): Poi[] {
  return parsePois(readFileSync(new URL('pois-krakow.json', FIXTURES), 'utf8')).items;
}

export function demoRoute(): GeoFix[] {
  return parseRoute(readFileSync(new URL('demo-route-krakow.json', FIXTURES), 'utf8')).items;
}

// Metres to degrees around Kraków (lat 50): good enough for building synthetic test walks.
export const M_LAT: number = 1 / 111195;
export const M_LON: number = 1 / 71475;
export const ORIGIN_LAT: number = 50.06;
export const ORIGIN_LON: number = 19.94;

// A fix `north` and `east` metres from the test origin, at time tS seconds.
export function fixAt(north: number, east: number, tS: number, accuracyM: number = 5): GeoFix {
  const f: GeoFix = { lat: ORIGIN_LAT + north * M_LAT, lon: ORIGIN_LON + east * M_LON, accuracyM: accuracyM, t: tS * 1000 };
  return f;
}

export function poiAt(id: string, north: number, east: number, importance: number = 0.5,
  role: PoiRole = PoiRole.SIGHT): Poi {
  const p: Poi = {
    id: id, name: id, summary: 'Zdanie pierwsze o ' + id + '. Zdanie drugie. Zdanie trzecie.',
    lat: ORIGIN_LAT + north * M_LAT, lon: ORIGIN_LON + east * M_LON,
    kind: 'building', wikidataId: null, imageUrl: null, sourceUrl: 'u',
    importance: importance, role: role, partOfId: null
  };
  return p;
}

// Deterministic pseudo-random noise in [-1, 1), so noisy tests never flake.
export class Noise {
  private s: number;
  constructor(seed: number) {
    this.s = seed;
  }
  next(): number {
    this.s = (this.s * 1103515245 + 12345) % 2147483648;
    return this.s / 2147483648 * 2 - 1;
  }
}

export function withNoise(route: GeoFix[], amplitudeM: number, seed: number): GeoFix[] {
  const n = new Noise(seed);
  return route.map((f: GeoFix) => {
    const g: GeoFix = { lat: f.lat + n.next() * amplitudeM * M_LAT, lon: f.lon + n.next() * amplitudeM * M_LON, accuracyM: f.accuracyM, t: f.t };
    return g;
  });
}

// Demo POIs: the fixtures carry importance/role/partOfId since issue #40 (PR #45).
export function demoPoisWithSignals(): Poi[] {
  return demoPois();
}

// Feeds a walk into a director: each fix, then one TICK per second until the next fix
// (and `tailS` seconds after the last one). Returns every action with its time.
export function runWalk(director: GuideDirector, fixes: GeoFix[], tailS: number = 60): GuideAction[] {
  const out: GuideAction[] = [];
  for (let i = 0; i < fixes.length; i++) {
    for (const a of director.step(GuideEvents.fix(fixes[i]))) {
      out.push(a);
    }
    const end = i + 1 < fixes.length ? fixes[i + 1].t : fixes[i].t + tailS * 1000;
    for (let t = fixes[i].t + 1000; t < end; t += 1000) {
      for (const a of director.step(GuideEvents.tick(t))) {
        out.push(a);
      }
    }
  }
  return out;
}

export function plays(actions: GuideAction[]): GuideAction[] {
  return actions.filter((a: GuideAction) => a.kind === GuideActionKind.PLAY_SEGMENT);
}
