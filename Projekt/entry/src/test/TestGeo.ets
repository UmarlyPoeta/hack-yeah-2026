import { GeoFix } from '../main/ets/model/GeoPoint';
import { Poi, PoiRole } from '../main/ets/model/Poi';
import { GuideDirector, GuideEvents } from '../main/ets/guide/GuideDirector';
import { GuideAction, GuideActionKind } from '../main/ets/guide/NarrationPlanner';
import { Segment } from '../main/ets/model/Segment';

// Helpers for synthetic walks around Kraków (lat 50). Mirrors guide-lab/test/helpers.ts.
export const M_LAT: number = 1 / 111195;
export const M_LON: number = 1 / 71475;
const ORIGIN_LAT: number = 50.06;
const ORIGIN_LON: number = 19.94;

export function fixAt(north: number, east: number, tS: number, accuracyM: number = 5): GeoFix {
  const f: GeoFix = { lat: ORIGIN_LAT + north * M_LAT, lon: ORIGIN_LON + east * M_LON, accuracyM: accuracyM, t: tS * 1000 };
  return f;
}

export function poiAt(id: string, north: number, east: number, importance: number = 0.5,
  role: PoiRole = PoiRole.SIGHT): Poi {
  const p: Poi = {
    id: id, name: id, summary: 'Zdanie pierwsze o ' + id + '. Zdanie drugie. Zdanie trzecie.',
    lat: ORIGIN_LAT + north * M_LAT, lon: ORIGIN_LON + east * M_LON,
    kind: null, wikidataId: null, imageUrl: null, sourceUrl: 'u',
    importance: importance, role: role, partOfId: null
  };
  return p;
}

// Walk north at 1.3 m/s, one fix per second.
export function walkNorth(fromM: number, toM: number, startS: number): GeoFix[] {
  const out: GeoFix[] = [];
  let t = startS;
  for (let m = fromM; m <= toM; m += 1.3) {
    out.push(fixAt(m, 0, t));
    t++;
  }
  return out;
}

export function standAt(north: number, fromS: number, seconds: number): GeoFix[] {
  const out: GeoFix[] = [];
  for (let k = 0; k < seconds; k++) {
    out.push(fixAt(north, 0, fromS + k));
  }
  return out;
}

// Each fix, then one TICK per second until the next one. Returns all actions.
export function runWalk(director: GuideDirector, fixes: GeoFix[]): GuideAction[] {
  const out: GuideAction[] = [];
  for (let i = 0; i < fixes.length; i++) {
    director.step(GuideEvents.fix(fixes[i])).forEach((a: GuideAction) => out.push(a));
    const end = i + 1 < fixes.length ? fixes[i + 1].t : fixes[i].t;
    for (let t = fixes[i].t + 1000; t < end; t += 1000) {
      director.step(GuideEvents.tick(t)).forEach((a: GuideAction) => out.push(a));
    }
  }
  return out;
}

export function playedSegments(actions: GuideAction[]): Segment[] {
  const out: Segment[] = [];
  for (const a of actions) {
    if (a.kind === GuideActionKind.PLAY_SEGMENT && a.segment !== null) {
      out.push(a.segment);
    }
  }
  return out;
}

// Deterministic pseudo-random noise in [-1, 1).
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
