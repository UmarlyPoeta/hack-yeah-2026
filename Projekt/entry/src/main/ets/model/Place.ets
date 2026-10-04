// A landmark shown by the UI: a Poi from the server plus its photo downloaded to the app sandbox.
// Kept as plain JSON-friendly fields, because the queue and the saved list are written to files.
import { GeoPoint } from './GeoPoint';
import { Poi, PoiRole } from './Poi';

export interface Place extends GeoPoint {
  id: string;            // Poi id, "plwiki:<pageid>"
  name: string;
  summary: string;       // Wikipedia intro, "Więcej o tym miejscu"
  wikidataId: string | null;
  importance: number;
  imageUrl: string;      // remote photo (Wikipedia thumbnail)
  imageFile: string;     // the same photo in the sandbox, '' until downloaded
  sourceUrl: string;     // Wikipedia article (CC BY-SA 4.0)
}

export function placeFromPoi(poi: Poi): Place {
  const place: Place = {
    id: poi.id,
    name: poi.name,
    summary: poi.summary,
    lat: poi.lat,
    lon: poi.lon,
    wikidataId: poi.wikidataId,
    importance: poi.importance,
    imageUrl: poi.imageUrl ?? '',
    imageFile: '',
    sourceUrl: poi.sourceUrl,
  };
  return place;
}

/** The Poi the templates and the server expect, rebuilt from a stored Place. */
export function poiFromPlace(place: Place): Poi {
  const poi: Poi = {
    id: place.id,
    name: place.name,
    summary: place.summary,
    lat: place.lat,
    lon: place.lon,
    kind: null,
    wikidataId: place.wikidataId,
    imageUrl: place.imageUrl.length > 0 ? place.imageUrl : null,
    sourceUrl: place.sourceUrl,
    importance: place.importance,
    role: PoiRole.SIGHT,
    partOfId: null,
  };
  return poi;
}

/** Image source for ArkUI: the downloaded file, else the remote URL. */
export function placeImage(place: Place): string {
  return place.imageFile.length > 0 ? `file://${place.imageFile}` : place.imageUrl;
}

/** "Barbakan w Krakowie" -> "Barbakan", "Kościół X (Kraków)" -> "Kościół X". */
export function shortName(place: Place): string {
  return place.name.replace(new RegExp('\\s*\\([^)]*\\)\\s*$'), '')
    .replace(new RegExp(' w [A-ZĄĆĘŁŃÓŚŹŻ][a-ząćęłńóśźż]+$'), '');
}

/** "350 m", "1,2 km". */
export function distanceLabel(m: number): string {
  return m < 1000 ? `${Math.max(10, Math.round(m / 10) * 10)} m` : `${(m / 1000).toFixed(1).replace('.', ',')} km`;
}
