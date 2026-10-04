// Requests for a place's narration. Texts are preloaded for the whole queue without voice; the server
// caches the text apart from the audio, so opening a place then waits only for the TTS.
import { SegmentRequest } from '../data/SegmentService';
import { Place } from '../model/Place';
import { Segment, SegmentKind } from '../model/Segment';
import { NARRATION_TIMEOUT_MS, Services } from './Services';
import { Settings } from './Settings';

const NARRATION_WORDS: number = 90;

function request(placeId: string, voice: boolean): SegmentRequest {
  const req: SegmentRequest = {
    kind: SegmentKind.ARRIVAL,
    poiId: placeId,
    fromPoiId: null,
    interests: Settings.interestList(),
    maxWords: NARRATION_WORDS,
    voice: voice,
  };
  return req;
}

/** Text only, in the background; repeated calls for the same place reuse the first one. */
export function preloadNarration(places: Place[]): void {
  for (const place of places) {
    Services.narration().prefetch(request(place.id, false), NARRATION_TIMEOUT_MS);
  }
}

/** Text and voice for the place screen. Never rejects (a local template after the timeout). */
export function narrationWithVoice(place: Place): Promise<Segment> {
  return Services.narration().request(request(place.id, true), NARRATION_TIMEOUT_MS);
}
