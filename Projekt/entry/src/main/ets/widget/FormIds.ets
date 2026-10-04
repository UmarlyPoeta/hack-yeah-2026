// Ids of the cards on the home screen, in a small file: the form extension and the app run in
// different processes, so an in-memory list or a cached Preferences instance would go stale.
import { fileIo as fs } from '@kit.CoreFileKit';

function file(filesDir: string): string {
  return `${filesDir}/forms.json`;
}

export function readFormIds(filesDir: string): string[] {
  try {
    return JSON.parse(fs.readTextSync(file(filesDir))) as string[];
  } catch (e) {
    return [];
  }
}

export function writeFormIds(filesDir: string, ids: string[]): void {
  try {
    const f = fs.openSync(file(filesDir), fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
    fs.writeSync(f.fd, JSON.stringify(ids));
    fs.closeSync(f);
  } catch (e) {
    // the card still works; it only misses updates from the app
  }
}
