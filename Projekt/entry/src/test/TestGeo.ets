import { GeoFix } from '../main/ets/model/GeoPoint';
import { Poi } from '../main/ets/model/Poi';

// Helpers for synthetic walks around Kraków (lat 50). Mirrors guide-lab/test/helpers.ts.
export const M_LAT: number = 1 / 111195;
export const M_LON: number = 1 / 71475;
const ORIGIN_LAT: number = 50.06;
const ORIGIN_LON: number = 19.94;

export function fixAt(north: number, east: number, tS: number, accuracyM: number = 5): GeoFix {
  const f: GeoFix = { lat: ORIGIN_LAT + north * M_LAT, lon: ORIGIN_LON + east * M_LON, accuracyM: accuracyM, t: tS * 1000 };
  return f;
}

export function poiAt(id: string, north: number, east: number): Poi {
  const p: Poi = {
    id: id, name: id, summary: 's', lat: ORIGIN_LAT + north * M_LAT, lon: ORIGIN_LON + east * M_LON,
    kind: null, wikidataId: null, imageUrl: null, sourceUrl: 'u'
  };
  return p;
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
