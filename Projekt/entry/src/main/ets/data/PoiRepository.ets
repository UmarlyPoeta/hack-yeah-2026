// POIs near the user: GET /v1/pois on our server, bundled rawfile data when the server is unreachable.
// Calls near() on every fix; it only queries again after the user moved more than 150 m.
import { GeoFix, GeoPoint } from '../model/GeoPoint';
import { Poi } from '../model/Poi';
import { HttpTransport, TextSource } from './HttpTransport';
import { parsePois } from './FixtureParser';
import { distanceM } from '../guide/geo';

export type PoiSource = 'live' | 'cache' | 'fixture' | 'none';

export const REFETCH_DISTANCE_M: number = 150;
export const MAX_POIS: number = 50;

// #56: the server only ever sees the centre of a ~150 m grid cell, never the fix itself. The user can be up to
// half a cell diagonal (~107 m) away from that centre, so the query radius grows by that margin and the exact
// distance filter runs here, on the phone.
export const COARSE_CELL_M: number = 150;
export const COARSE_MARGIN_M: number = Math.ceil(COARSE_CELL_M * Math.SQRT2 / 2);
const SERVER_MAX_RADIUS_M: number = 1000;
const METERS_PER_DEG_LAT: number = 111320;

/** Centre of the grid cell (cellM × cellM) that contains the point. */
export function coarsePosition(p: GeoPoint, cellM: number = COARSE_CELL_M): GeoPoint {
  const dLat = cellM / METERS_PER_DEG_LAT;
  const lat = (Math.floor(p.lat / dLat) + 0.5) * dLat;
  // longitude step from the row's centre latitude, so every point of a row shares the same columns
  const dLon = cellM / (METERS_PER_DEG_LAT * Math.cos(lat * Math.PI / 180));
  const lon = (Math.floor(p.lon / dLon) + 0.5) * dLon;
  const centre: GeoPoint = { lat: lat, lon: lon };
  return centre;
}

interface PoisSource {
  source?: string;
}

export class PoiRepository {
  /** Where the last result came from: server ('live' | 'cache'), bundled data ('fixture'), or nothing yet. */
  lastSource: PoiSource = 'none';

  private http: HttpTransport | null;
  private baseUrl: string;
  private fixtures: TextSource;
  private timeoutMs: number;
  private fixturePois: Poi[] | null = null;
  private lastPois: Poi[] = [];
  private lastPosition: GeoPoint = { lat: 0, lon: 0 };
  private lastRadiusM: number = -1;

  /** http = null or empty baseUrl: offline mode, bundled data only. */
  constructor(http: HttpTransport | null, baseUrl: string, fixtures: TextSource, timeoutMs: number) {
    this.http = http;
    this.baseUrl = baseUrl.replace(new RegExp('/+$'), '');
    this.fixtures = fixtures;
    this.timeoutMs = timeoutMs;
  }

  /** POIs within radiusM of the fix, sorted by distanceM, max 50. Never rejects. */
  async near(fix: GeoFix, radiusM: number): Promise<Poi[]> {
    if (this.lastRadiusM === radiusM &&
      distanceM(fix, this.lastPosition) <= REFETCH_DISTANCE_M) {
      return withDistances(this.lastPois, fix, radiusM);
    }
    let pois: Poi[] | null = await this.fetchFromServer(fix, radiusM);
    if (pois === null) {
      pois = await this.loadFixtures();
      this.lastSource = 'fixture';
    }
    this.lastPois = pois;
    const position: GeoPoint = { lat: fix.lat, lon: fix.lon };
    this.lastPosition = position;
    this.lastRadiusM = radiusM;
    return withDistances(pois, fix, radiusM);
  }

  /** POI by id from the last result or the bundled data (e.g. to show the source of a segment). */
  async get(id: string): Promise<Poi | null> {
    const fromLast = this.lastPois.find((p: Poi) => p.id === id);
    if (fromLast !== undefined) {
      return fromLast;
    }
    const fromFixtures = (await this.loadFixtures()).find((p: Poi) => p.id === id);
    return fromFixtures !== undefined ? fromFixtures : null;
  }

  private async fetchFromServer(fix: GeoFix, radiusM: number): Promise<Poi[] | null> {
    if (this.http === null || this.baseUrl.length === 0) {
      return null;
    }
    const cell = coarsePosition(fix);
    const radius = Math.min(SERVER_MAX_RADIUS_M, Math.round(radiusM) + COARSE_MARGIN_M);
    const url = `${this.baseUrl}/v1/pois?lat=${cell.lat.toFixed(5)}&lon=${cell.lon.toFixed(5)}&radius=${radius}`;
    try {
      const res = await this.http.get(url, this.timeoutMs);
      if (res.status !== 200) {
        return null;
      }
      // same validation and defaults (importance, role, partOfId) as the bundled data
      const parsed = parsePois(res.body);
      if (parsed.error !== null) {
        return null;
      }
      const data = JSON.parse(res.body) as PoisSource;
      this.lastSource = data.source === 'fixture' ? 'fixture' : (data.source === 'cache' ? 'cache' : 'live');
      return parsed.items;
    } catch (e) {
      return null;
    }
  }

  private async loadFixtures(): Promise<Poi[]> {
    if (this.fixturePois !== null) {
      return this.fixturePois;
    }
    try {
      this.fixturePois = parsePois(await this.fixtures.read()).items;
    } catch (e) {
      this.fixturePois = [];
    }
    return this.fixturePois;
  }
}

function withDistances(pois: Poi[], fix: GeoFix, radiusM: number): Poi[] {
  const out: Poi[] = [];
  for (const p of pois) {
    const d = Math.round(distanceM(fix, p));
    if (d <= radiusM) {
      const copy: Poi = {
        id: p.id,
        name: p.name,
        summary: p.summary,
        lat: p.lat,
        lon: p.lon,
        kind: p.kind,
        wikidataId: p.wikidataId,
        imageUrl: p.imageUrl,
        sourceUrl: p.sourceUrl,
        importance: p.importance,
        role: p.role,
        partOfId: p.partOfId,
        distanceM: d,
      };
      out.push(copy);
    }
  }
  out.sort((a: Poi, b: Poi) => (a.distanceM as number) - (b.distanceM as number));
  return out.slice(0, MAX_POIS);
}
