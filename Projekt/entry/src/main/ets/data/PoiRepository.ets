// POIs near the user: GET /v1/pois on our server, bundled rawfile data when the server is unreachable.
// Calls near() on every fix; it only queries again after the user moved more than 150 m.
import { GeoFix } from '../model/GeoFix';
import { Poi } from '../model/Poi';
import { HttpTransport, TextSource } from './HttpTransport';

export type PoiSource = 'live' | 'cache' | 'fixture' | 'none';

export const REFETCH_DISTANCE_M: number = 150;
export const MAX_POIS: number = 50;

interface PoisResponse {
  pois: Poi[];
  source: string;
}

interface FixtureFile {
  pois: Poi[];
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
  private lastLat: number = 0;
  private lastLon: number = 0;
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
      haversineM(fix.lat, fix.lon, this.lastLat, this.lastLon) <= REFETCH_DISTANCE_M) {
      return withDistances(this.lastPois, fix, radiusM);
    }
    let pois: Poi[] | null = await this.fetchFromServer(fix, radiusM);
    if (pois === null) {
      pois = await this.loadFixtures();
      this.lastSource = 'fixture';
    }
    this.lastPois = pois;
    this.lastLat = fix.lat;
    this.lastLon = fix.lon;
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
    const url = `${this.baseUrl}/v1/pois?lat=${fix.lat.toFixed(6)}&lon=${fix.lon.toFixed(6)}&radius=${Math.round(radiusM)}`;
    try {
      const res = await this.http.get(url, this.timeoutMs);
      if (res.status !== 200) {
        return null;
      }
      const data = JSON.parse(res.body) as PoisResponse;
      if (!Array.isArray(data.pois)) {
        return null;
      }
      this.lastSource = data.source === 'fixture' ? 'fixture' : (data.source === 'cache' ? 'cache' : 'live');
      return data.pois.filter(isValidPoi);
    } catch (e) {
      return null;
    }
  }

  private async loadFixtures(): Promise<Poi[]> {
    if (this.fixturePois !== null) {
      return this.fixturePois;
    }
    try {
      const data = JSON.parse(await this.fixtures.read()) as FixtureFile;
      this.fixturePois = Array.isArray(data.pois) ? data.pois.filter(isValidPoi) : [];
    } catch (e) {
      this.fixturePois = [];
    }
    return this.fixturePois;
  }
}

function isValidPoi(p: Poi): boolean {
  return p !== null && typeof p.id === 'string' && typeof p.name === 'string' &&
    typeof p.lat === 'number' && typeof p.lon === 'number';
}

function withDistances(pois: Poi[], fix: GeoFix, radiusM: number): Poi[] {
  const out: Poi[] = [];
  for (const p of pois) {
    const d = Math.round(haversineM(fix.lat, fix.lon, p.lat, p.lon));
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
        distanceM: d,
      };
      out.push(copy);
    }
  }
  out.sort((a: Poi, b: Poi) => (a.distanceM as number) - (b.distanceM as number));
  return out.slice(0, MAX_POIS);
}

// Local copy until guide/geo.ets (P2) exists; switch to it then.
function haversineM(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const rad = Math.PI / 180;
  const dp = (lat2 - lat1) * rad;
  const dl = (lon2 - lon1) * rad;
  const h = Math.sin(dp / 2) * Math.sin(dp / 2) +
    Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(dl / 2) * Math.sin(dl / 2);
  return 2 * 6371000 * Math.asin(Math.sqrt(h));
}
