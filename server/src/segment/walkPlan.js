// Which segments a walk along a route will ask for (used by `npm run warm`). Mirrors the budgets of the app's
// NarrationPlanner (docs/ARCHITECTURE.md §2.3): words = clamp(ETA × 2.5 words/s × share, min, max).
import { haversineM } from '../geo.js';
import { MAX_WORDS_BUCKET } from './SegmentGenerator.js';

const ARRIVAL_M = 35;
const WORDS_PER_S = 2.5;

const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));
const bucket = (w) => Math.ceil(w / MAX_WORDS_BUCKET) * MAX_WORDS_BUCKET;

/** POIs the route passes within ARRIVAL_M, in the order they are reached, with the time `t` (s) of arrival. */
export function stopsAlong(route, pois, arrivalM = ARRIVAL_M) {
  const stops = [];
  for (const poi of pois) {
    let best = null;
    for (const pt of route) {
      const d = haversineM(pt.lat, pt.lon, poi.lat, poi.lon);
      if (d <= arrivalM && (!best || d < best.d)) best = { d, t: pt.t };
    }
    if (best) stops.push({ poi, t: best.t });
  }
  return stops.sort((a, b) => a.t - b.t);
}

/**
 * @param {{ lat: number, lon: number, t: number }[]} route
 * @param {{ id: string, lat: number, lon: number }[]} pois
 * @param {{ interests?: string[], limit?: number }} [opts] limit = number of stops (each costs TTS characters)
 * @returns {{ kind: string, poiId: string, fromPoiId: string|null, interests: string[], maxWords: number }[]}
 */
export function walkPlan(route, pois, { interests = [], limit = Infinity } = {}) {
  const stops = stopsAlong(route, pois).slice(0, limit);
  const req = (kind, poiId, fromPoiId, maxWords) => ({ kind, poiId, fromPoiId, interests, maxWords: bucket(maxWords) });
  const plan = [];
  if (stops.length) plan.push(req('WELCOME', stops[0].poi.id, null, 40));
  stops.forEach((stop, i) => {
    const next = stops[i + 1];
    const eta = next ? next.t - stop.t : 60;
    plan.push(req('ARRIVAL', stop.poi.id, null, clamp(eta * WORDS_PER_S * 0.7, 40, 120)));
    if (next && eta >= 25) plan.push(req('BRIDGE', next.poi.id, stop.poi.id, clamp(eta * WORDS_PER_S * 0.6, 20, 70)));
  });
  return plan;
}
