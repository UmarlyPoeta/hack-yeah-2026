// Data for the home screen card: the first landmark of the saved queue (filesDir/queue/queue.json),
// read the same way by the form extension (onAddForm) and by the app (store/Widgets.ets).
import { fileIo as fs } from '@kit.CoreFileKit';
import { formBindingData } from '@kit.FormKit';
import { distanceM } from '../guide/geo';
import { distanceLabel, Place, shortName } from '../model/Place';

interface QueueFile {
  places: Place[];
  lat: number;
  lon: number;
}

/** Fields the card page reads from its LocalStorage. */
interface CardData {
  placeId: string;
  name: string;
  distance: string;
  imageKey: string;   // the card shows memory://<imageKey>; a new key per place makes it reload
  hasPlace: boolean;
  formImages?: Record<string, number>;
}

export function cardBindingData(filesDir: string): formBindingData.FormBindingData {
  const data: CardData = { placeId: '', name: '', distance: '', imageKey: '', hasPlace: false };
  try {
    const text = fs.readTextSync(`${filesDir}/queue/queue.json`);
    const queue = JSON.parse(text) as QueueFile;
    const place = (queue.places ?? [])[0];
    if (place !== undefined) {
      data.placeId = place.id;
      data.name = shortName(place);
      data.hasPlace = true;
      if (queue.lat !== 0 || queue.lon !== 0) {
        data.distance = `${distanceLabel(distanceM({ lat: queue.lat, lon: queue.lon }, place))} od ciebie`;
      }
      if (place.imageFile.length > 0 && fs.accessSync(place.imageFile)) {
        const key = `img_${place.id.replace(new RegExp('[^A-Za-z0-9]', 'g'), '_')}`;
        const images: Record<string, number> = {};
        images[key] = fs.openSync(place.imageFile, fs.OpenMode.READ_ONLY).fd;
        data.imageKey = key;
        data.formImages = images;
      }
    }
  } catch (e) {
    // no queue yet: the card shows the empty state
  }
  return formBindingData.createFormBindingData(data);
}
