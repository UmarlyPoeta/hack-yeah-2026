// The town the user is in, for the card on "Odkrywaj": name from OpenStreetMap (Nominatim reverse
// geocoding), description and photo from the Polish Wikipedia summary. Stored in filesDir so it shows offline.
// AppStorage: 'city' (City | null).
import { common } from '@kit.AbilityKit';
import { distanceM } from '../guide/geo';
import { GeoFix, GeoPoint } from '../model/GeoPoint';
import { fetchText, readText, removeFile, writeText } from './LocalFiles';

const REFETCH_DISTANCE_M: number = 5000;

export interface City extends GeoPoint {
  name: string;
  description: string;   // "miasto w Polsce, w województwie małopolskim"
  extract: string;       // intro of the article
  imageUrl: string;
  sourceUrl: string;     // lat/lon: where it was looked up
}

interface NominatimAddress {
  city?: string;
  town?: string;
  village?: string;
}

interface NominatimResult {
  address?: NominatimAddress;
}

interface WikiImage {
  source: string;
}

interface WikiUrls {
  page: string;
}

interface WikiContentUrls {
  mobile?: WikiUrls;
  desktop?: WikiUrls;
}

interface WikiSummary {
  type: string;
  title: string;
  description?: string;
  extract?: string;
  originalimage?: WikiImage;
  thumbnail?: WikiImage;
  content_urls?: WikiContentUrls;
}

export class CityInfo {
  private static file: string = '';
  private static busy: boolean = false;

  static init(context: common.Context): void {
    CityInfo.file = `${context.filesDir}/queue/city.json`;
    const text = readText(CityInfo.file);
    if (text !== null) {
      try {
        AppStorage.setOrCreate<City | null>('city', JSON.parse(text) as City);
      } catch (e) {
        AppStorage.setOrCreate<City | null>('city', null);
      }
    }
  }

  /** Looks the town up again only after the user moved more than 5 km. Never rejects. */
  static async update(fix: GeoFix): Promise<void> {
    const current = AppStorage.get<City | null>('city') ?? null;
    if (CityInfo.busy || (current !== null && distanceM(fix, current) < REFETCH_DISTANCE_M)) {
      return;
    }
    CityInfo.busy = true;
    try {
      const name = await CityInfo.townName(fix);
      if (name === null) {
        return;
      }
      const city = await CityInfo.summary(name, fix);
      if (city !== null) {
        writeText(CityInfo.file, JSON.stringify(city));
        AppStorage.setOrCreate<City | null>('city', city);
      }
    } finally {
      CityInfo.busy = false;
    }
  }

  static reset(): void {
    removeFile(CityInfo.file);
    AppStorage.setOrCreate<City | null>('city', null);
  }

  private static async townName(fix: GeoFix): Promise<string | null> {
    const text = await fetchText('https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10' +
      `&accept-language=pl&lat=${fix.lat.toFixed(5)}&lon=${fix.lon.toFixed(5)}`);
    if (text === null) {
      return null;
    }
    try {
      const a = (JSON.parse(text) as NominatimResult).address;
      return a?.city ?? a?.town ?? a?.village ?? null;
    } catch (e) {
      return null;
    }
  }

  private static async summary(name: string, fix: GeoFix): Promise<City | null> {
    const text = await fetchText(`https://pl.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(name)}`);
    if (text === null) {
      return null;
    }
    try {
      const s = JSON.parse(text) as WikiSummary;
      if (s.type !== 'standard' || (s.extract ?? '').length === 0) {
        return null;
      }
      const city: City = {
        name: s.title,
        description: s.description ?? '',
        extract: s.extract ?? '',
        // the summary thumbnail is 320 px wide; Commons serves any width from the same path
        imageUrl: (s.thumbnail?.source ?? '').replace(new RegExp('/\\d+px-'), '/1280px-'),
        sourceUrl: s.content_urls?.mobile?.page ?? s.content_urls?.desktop?.page ?? '',
        lat: fix.lat,
        lon: fix.lon,
      };
      return city;
    } catch (e) {
      return null;
    }
  }
}
