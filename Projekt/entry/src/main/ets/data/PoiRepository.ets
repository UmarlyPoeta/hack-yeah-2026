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
    const url = `${this.baseUrl}/v1/pois?lat=${fix.lat.toFixed(6)}&lon=${fix.lon.toFixed(6)}&radius=${Math.round(radiusM)}`;
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
