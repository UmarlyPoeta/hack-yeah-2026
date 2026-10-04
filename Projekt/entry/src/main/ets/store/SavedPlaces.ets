// Landmarks saved for later ("Zapisane"). Each keeps its own copy of the photo, because the queue
// deletes its photos when a place rotates out.
// AppStorage: 'saved' (Place[], newest first).
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Place, poiFromPlace } from '../model/Place';
import { copyFile, ensureDir, readText, removeFile, writeText } from './LocalFiles';
import { fileId } from './PlaceQueue';
import { Services } from './Services';

const DOMAIN: number = 0x0000;
const TAG: string = 'SavedPlaces';

export class SavedPlaces {
  private static dir: string = '';
  private static places: Place[] = [];

  static init(context: common.Context): void {
    if (SavedPlaces.dir.length > 0) {
      return;
    }
    SavedPlaces.dir = `${context.filesDir}/saved`;
    ensureDir(`${SavedPlaces.dir}/img`);
    const text = readText(`${SavedPlaces.dir}/saved.json`);
    if (text !== null) {
      try {
        SavedPlaces.places = JSON.parse(text) as Place[];
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'bad saved.json: %{public}s', JSON.stringify(e));
      }
    }
    SavedPlaces.places.forEach((p: Place) => Services.remember(poiFromPlace(p)));
    SavedPlaces.publish();
  }

  static has(id: string): boolean {
    return SavedPlaces.places.some((p: Place) => p.id === id);
  }

  static get(id: string): Place | null {
    return SavedPlaces.places.find((p: Place) => p.id === id) ?? null;
  }

  static toggle(place: Place): void {
    if (SavedPlaces.has(place.id)) {
      SavedPlaces.remove(place.id);
    } else {
      SavedPlaces.add(place);
    }
  }

  static add(place: Place): void {
    const copy: Place = {
      id: place.id,
      name: place.name,
      summary: place.summary,
      lat: place.lat,
      lon: place.lon,
      wikidataId: place.wikidataId,
      importance: place.importance,
      imageUrl: place.imageUrl,
      imageFile: '',
      sourceUrl: place.sourceUrl,
    };
    const file = `${SavedPlaces.dir}/img/${fileId(place.id)}.jpg`;
    if (place.imageFile.length > 0 && copyFile(place.imageFile, file)) {
      copy.imageFile = file;
    }
    SavedPlaces.places.unshift(copy);
    SavedPlaces.save();
  }

  static remove(id: string): void {
    const place = SavedPlaces.get(id);
    if (place === null) {
      return;
    }
    removeFile(place.imageFile);
    SavedPlaces.places = SavedPlaces.places.filter((p: Place) => p.id !== id);
    SavedPlaces.save();
  }

  static reset(): void {
    SavedPlaces.places.forEach((p: Place) => removeFile(p.imageFile));
    SavedPlaces.places = [];
    SavedPlaces.save();
  }

  private static save(): void {
    writeText(`${SavedPlaces.dir}/saved.json`, JSON.stringify(SavedPlaces.places));
    SavedPlaces.publish();
  }

  private static publish(): void {
    AppStorage.setOrCreate<Place[]>('saved', SavedPlaces.places.slice());
  }
}
