import { GeoFix } from '../model/GeoPoint';
import { Poi } from '../model/Poi';

// Parses the bundled demo data (rawfile/pois-krakow.json, rawfile/demo-route-krakow.json).
// Input is the file text, so this stays pure: reading the rawfile is the caller's job.
// Bad entries are skipped and counted instead of crashing the app.

// Shapes of the raw JSON. Every field is optional because we cannot trust the file.
interface RawPoi {
  id?: string;
  name?: string;
  summary?: string;
  lat?: number;
  lon?: number;
  kind?: string | null;
  wikidataId?: string | null;
  imageUrl?: string | null;
  sourceUrl?: string;
}

interface RawPoiFile {
  pois?: RawPoi[];
}

interface RawRoutePoint {
  lat?: number;
  lon?: number;
  t?: number; // seconds from the start of the walk
}

export interface ParseResult<T> {
  items: T[];
  rejected: number;      // entries skipped because a required field was missing or invalid
  error: string | null;  // set when the whole file could not be read
}

// The demo route has no accuracy; this is a typical good GPS fix outdoors.
export const DEFAULT_ROUTE_ACCURACY_M: number = 5;

function isValidLatLon(lat: number | undefined, lon: number | undefined): boolean {
  return typeof lat === 'number' && typeof lon === 'number'
    && isFinite(lat) && isFinite(lon)
    && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
}

function isNonEmptyString(value: string | undefined): boolean {
  return typeof value === 'string' && value.length > 0;
}

function nullableString(value: string | null | undefined): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

function toPoi(raw: RawPoi): Poi | null {
  if (!isNonEmptyString(raw.id) || !isNonEmptyString(raw.name) || !isNonEmptyString(raw.summary)
    || !isNonEmptyString(raw.sourceUrl) || !isValidLatLon(raw.lat, raw.lon)) {
    return null;
  }
  const poi: Poi = {
    id: raw.id as string,
    name: raw.name as string,
    summary: raw.summary as string,
    lat: raw.lat as number,
    lon: raw.lon as number,
    kind: nullableString(raw.kind),
    wikidataId: nullableString(raw.wikidataId),
    imageUrl: nullableString(raw.imageUrl),
    sourceUrl: raw.sourceUrl as string
  };
  return poi;
}

export function parsePois(text: string): ParseResult<Poi> {
  const result: ParseResult<Poi> = { items: [], rejected: 0, error: null };
  let file: RawPoiFile;
  try {
    file = JSON.parse(text) as RawPoiFile;
  } catch (e) {
    result.error = 'invalid JSON';
    return result;
  }
  if (file === null || typeof file !== 'object' || !Array.isArray(file.pois)) {
    result.error = 'missing "pois" array';
    return result;
  }
  const seen = new Set<string>();
  for (const raw of file.pois) {
    const poi = raw !== null && typeof raw === 'object' ? toPoi(raw) : null;
    if (poi === null || seen.has(poi.id)) {
      result.rejected++;
      continue;
    }
    seen.add(poi.id);
    result.items.push(poi);
  }
  return result;
}

export function parseRoute(text: string): ParseResult<GeoFix> {
  const result: ParseResult<GeoFix> = { items: [], rejected: 0, error: null };
  let points: RawRoutePoint[];
  try {
    points = JSON.parse(text) as RawRoutePoint[];
  } catch (e) {
    result.error = 'invalid JSON';
    return result;
  }
  if (!Array.isArray(points)) {
    result.error = 'route must be a JSON array';
    return result;
  }
  let lastT = -1;
  for (const raw of points) {
    const ok = raw !== null && typeof raw === 'object'
      && isValidLatLon(raw.lat, raw.lon)
      && typeof raw.t === 'number' && isFinite(raw.t) && raw.t >= 0;
    const tMs = ok ? Math.round((raw.t as number) * 1000) : -1;
    // time must move forward, otherwise speed calculations later divide by zero or go negative
    if (!ok || tMs <= lastT) {
      result.rejected++;
      continue;
    }
    lastT = tMs;
    const fix: GeoFix = {
      lat: raw.lat as number,
      lon: raw.lon as number,
      accuracyM: DEFAULT_ROUTE_ACCURACY_M,
      t: tMs
    };
    result.items.push(fix);
  }
  return result;
}
