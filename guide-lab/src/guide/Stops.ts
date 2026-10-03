import { Poi, PoiRole } from '../model/Poi';
import { GeoPoint } from '../model/GeoPoint';
import { distanceM } from './geo';

// Groups places into stops: what the guide treats as one thing to talk about.
// Kościół Mariacki and its parish, or Sukiennice and the gallery inside, are one stop.
// Areas (streets, squares) are never stops. Algorithm: docs/ARCHITECTURE.md §2.3.

export interface Stop {
  id: string;          // id of the anchor place
  anchor: Poi;         // the most important place of the group: what ARRIVAL is about
  members: Poi[];      // anchor first, then the rest ("Obok: ...")
  importance: number;  // the anchor's importance
}

export const CLUSTER_RADIUS_M: number = 40;
// Relative selection: a stop is worth an ARRIVAL when it is in the top ~30% of stops nearby,
// so small towns get a guide too, not only Kraków.
export const LOCAL_RADIUS_M: number = 500;
export const LOCAL_TOP_SHARE: number = 0.3;
export const MIN_IMPORTANCE: number = 0.15;   // never narrate below this as a main stop (~1 language version)
export const ALWAYS_IMPORTANCE: number = 0.6; // always narrate from here (~10 language versions)

function byImportance(a: Poi, b: Poi): number {
  if (b.importance !== a.importance) {
    return b.importance - a.importance;
  }
  return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
}

export function buildStops(pois: Poi[]): Stop[] {
  const sights = pois.filter((p: Poi) => p.role !== PoiRole.AREA).sort(byImportance);
  const ids = new Set<string>(sights.map((p: Poi) => p.id));
  const stopOf = new Map<string, Stop>();
  const stops: Stop[] = [];
  // 1) clusters by distance, the most important place of each cluster is the anchor;
  //    places declared as part of another sight are attached in step 2 instead
  for (const p of sights) {
    if (stopOf.has(p.id) || (p.partOfId !== null && ids.has(p.partOfId))) {
      continue;
    }
    const stop: Stop = { id: p.id, anchor: p, members: [p], importance: p.importance };
    stops.push(stop);
    stopOf.set(p.id, stop);
    for (const q of sights) {
      if (!stopOf.has(q.id) && !(q.partOfId !== null && ids.has(q.partOfId)) && distanceM(p, q) <= CLUSTER_RADIUS_M) {
        stop.members.push(q);
        stopOf.set(q.id, stop);
      }
    }
  }
  // 2) "part of": join the parent's stop (parents may themselves be parts, so repeat until stable)
  let changed = true;
  while (changed) {
    changed = false;
    for (const p of sights) {
      if (stopOf.has(p.id) || p.partOfId === null) {
        continue;
      }
      const parentStop = stopOf.get(p.partOfId);
      if (parentStop !== undefined) {
        parentStop.members.push(p);
        stopOf.set(p.id, parentStop);
        changed = true;
      }
    }
  }
  // cycles or missing parents: the place becomes a stop of its own
  for (const p of sights) {
    if (!stopOf.has(p.id)) {
      const stop: Stop = { id: p.id, anchor: p, members: [p], importance: p.importance };
      stops.push(stop);
      stopOf.set(p.id, stop);
    }
  }
  return stops;
}

// Distance from a point to the nearest member of a stop.
export function distanceToStop(from: GeoPoint, stop: Stop): number {
  let best = Number.MAX_VALUE;
  for (const m of stop.members) {
    best = Math.min(best, distanceM(from, m));
  }
  return best;
}

// Importance a stop needs here to get its own ARRIVAL: top LOCAL_TOP_SHARE of the stops within
// LOCAL_RADIUS_M, but never below MIN_IMPORTANCE and never above ALWAYS_IMPORTANCE.
export function localThreshold(position: GeoPoint, stops: Stop[]): number {
  const nearby: number[] = [];
  for (const s of stops) {
    if (distanceM(position, s.anchor) <= LOCAL_RADIUS_M) {
      nearby.push(s.importance);
    }
  }
  if (nearby.length === 0) {
    return ALWAYS_IMPORTANCE;
  }
  nearby.sort((a: number, b: number) => b - a);
  const index = Math.min(nearby.length - 1, Math.floor(nearby.length * LOCAL_TOP_SHARE));
  return Math.min(ALWAYS_IMPORTANCE, Math.max(MIN_IMPORTANCE, nearby[index]));
}
