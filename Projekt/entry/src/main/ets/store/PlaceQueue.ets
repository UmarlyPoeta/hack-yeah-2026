// Queue of nearby landmarks with their photos, so the app always has something to show.
// - refill(): asks the server for landmarks near the user, downloads each photo, and appends the place.
//   A full queue drops its first place for every new one (one new place per refill).
// - The queue, the photos and the ids already shown are written to filesDir, so after a restart the
//   last queue is on screen at once, also without a network.
// AppStorage: 'queue' (Place[]), 'queueLoading' (boolean).
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { distanceM } from '../guide/geo';
import { GeoFix } from '../model/GeoPoint';
import { Poi, PoiRole } from '../model/Poi';
import { Place, placeFromPoi, poiFromPlace } from '../model/Place';
import { download, ensureDir, readText, removeFile, writeText } from './LocalFiles';
import { preloadNarration } from './Narration';
import { Services } from './Services';

const DOMAIN: number = 0x0000;
const TAG: string = 'PlaceQueue';
export const QUEUE_SIZE: number = 8;
const SEARCH_RADIUS_M: number = 1000;
const STALE_DISTANCE_M: number = 3000;   // places this far from the user leave the queue
const MAX_SEEN: number = 300;

interface QueueFile {
  places: Place[];
  seen: string[];
  lat: number;
  lon: number;
}

export class PlaceQueue {
  private static dir: string = '';
  private static places: Place[] = [];
  private static seen: string[] = [];
  private static busy: boolean = false;

  /** Restores the saved queue (and the last known position) into AppStorage. */
  static init(context: common.Context): void {
    if (PlaceQueue.dir.length > 0) {
      return;
    }
    PlaceQueue.dir = `${context.filesDir}/queue`;
    ensureDir(`${PlaceQueue.dir}/img`);
    const text = readText(`${PlaceQueue.dir}/queue.json`);
    if (text !== null) {
      try {
        const data = JSON.parse(text) as QueueFile;
        PlaceQueue.places = data.places ?? [];
        PlaceQueue.seen = data.seen ?? [];
        if ((AppStorage.get<number>('userLat') ?? 0) === 0 && data.lat !== 0) {
          AppStorage.setOrCreate<number>('userLat', data.lat);
          AppStorage.setOrCreate<number>('userLon', data.lon);
        }
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'bad queue.json: %{public}s', JSON.stringify(e));
      }
    }
    PlaceQueue.places.forEach((p: Place) => Services.remember(poiFromPlace(p)));
    PlaceQueue.publish();
  }

  static get(id: string): Place | null {
    return PlaceQueue.places.find((p: Place) => p.id === id) ?? null;
  }

  /** Adds landmarks near fix until the queue is full, or one new landmark to a full queue. Never rejects. */
  static async refill(fix: GeoFix): Promise<void> {
    if (PlaceQueue.busy || PlaceQueue.dir.length === 0) {
      return;
    }
    PlaceQueue.busy = true;
    AppStorage.setOrCreate<boolean>('queueLoading', true);
    try {
      // the user moved away: places far behind are no longer worth showing
      const stale = PlaceQueue.places.filter((p: Place) => distanceM(fix, p) > STALE_DISTANCE_M);
      stale.forEach((p: Place) => PlaceQueue.drop(p));
      if (stale.length > 0) {
        PlaceQueue.save(fix);
      }

      const pois = await Services.pois().near(fix, SEARCH_RADIUS_M);
      const candidates = pois
        .filter((p: Poi) => PlaceQueue.isCandidate(p))
        .sort((a: Poi, b: Poi) => PlaceQueue.score(b) - PlaceQueue.score(a));
      let wanted = PlaceQueue.places.length < QUEUE_SIZE ? QUEUE_SIZE - PlaceQueue.places.length : 1;
      for (const poi of candidates) {
        if (wanted <= 0) {
          break;
        }
        const place = placeFromPoi(poi);
        const file = `${PlaceQueue.dir}/img/${fileId(place.id)}.jpg`;
        if (!await download(place.imageUrl, file)) {
          continue;   // no photo, no card: try the next landmark
        }
        place.imageFile = file;
        if (PlaceQueue.places.length >= QUEUE_SIZE) {
          PlaceQueue.drop(PlaceQueue.places[0]);
        }
        PlaceQueue.places.push(place);
        Services.remember(poi);
        preloadNarration([place]);   // the text is ready before the user opens the place
        wanted--;
        PlaceQueue.save(fix);   // after every photo, so the screen fills up one card at a time
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'refill failed: %{public}s', JSON.stringify(e));
    } finally {
      PlaceQueue.busy = false;
      AppStorage.setOrCreate<boolean>('queueLoading', false);
    }
  }

  /** The user listened to this place: it leaves the queue and does not come back. */
  static visited(id: string): void {
    const place = PlaceQueue.get(id);
    if (place !== null) {
      PlaceQueue.drop(place);
      PlaceQueue.save(null);
    }
  }

  /** Forgets the queue, its photos and the places already shown. */
  static reset(): void {
    PlaceQueue.places.forEach((p: Place) => removeFile(p.imageFile));
    PlaceQueue.places = [];
    PlaceQueue.seen = [];
    removeFile(`${PlaceQueue.dir}/queue.json`);
    AppStorage.setOrCreate<number>('userLat', 0);
    AppStorage.setOrCreate<number>('userLon', 0);
    PlaceQueue.publish();
  }

  private static isCandidate(poi: Poi): boolean {
    return poi.role === PoiRole.SIGHT && poi.imageUrl !== null && poi.summary.length > 0 &&
      PlaceQueue.get(poi.id) === null && !PlaceQueue.seen.includes(poi.id);
  }

  /** Well-known places first, nearer ones break ties. */
  private static score(poi: Poi): number {
    return poi.importance - 0.5 * (poi.distanceM ?? 0) / SEARCH_RADIUS_M;
  }

  private static drop(place: Place): void {
    PlaceQueue.places = PlaceQueue.places.filter((p: Place) => p.id !== place.id);
    PlaceQueue.seen.push(place.id);
    if (PlaceQueue.seen.length > MAX_SEEN) {
      PlaceQueue.seen = PlaceQueue.seen.slice(-MAX_SEEN);
    }
    removeFile(place.imageFile);   // saved places keep their own copy (SavedPlaces)
  }

  private static save(fix: GeoFix | null): void {
    const data: QueueFile = {
      places: PlaceQueue.places,
      seen: PlaceQueue.seen,
      lat: fix?.lat ?? (AppStorage.get<number>('userLat') ?? 0),
      lon: fix?.lon ?? (AppStorage.get<number>('userLon') ?? 0),
    };
    writeText(`${PlaceQueue.dir}/queue.json`, JSON.stringify(data));
    PlaceQueue.publish();
  }

  private static publish(): void {
    AppStorage.setOrCreate<Place[]>('queue', PlaceQueue.places.slice());
  }
}

export function fileId(id: string): string {
  return id.replace(new RegExp('[^A-Za-z0-9_-]', 'g'), '_');
}
