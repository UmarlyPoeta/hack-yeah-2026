// Narration without the screen:
// - "Rozpocznij" in the notification (on the phone or on a paired watch) plays the place on the phone
//   at once, without opening the app: the button sends a common event that this class receives.
// - "Tryb bez patrzenia" (off by default, switched on in "Moje"): next to a landmark the story starts by
//   itself, with a vibration.
// Playback shows in the control centre and on the lock screen (NarrationSession).
import { common } from '@kit.AbilityKit';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { vibrator } from '@kit.SensorServiceKit';
import { NarrationSession } from '../audio/NarrationSession';
import { NarratorPlayer, PlaybackListener } from '../audio/NarratorPlayer';
import { distanceM } from '../guide/geo';
import { GeoFix } from '../model/GeoPoint';
import { Place } from '../model/Place';
import { narrationWithVoice } from './Narration';
import { PlaceQueue } from './PlaceQueue';
import { SavedPlaces } from './SavedPlaces';

const DOMAIN: number = 0x0000;
const TAG: string = 'HandsFree';
export const ARRIVAL_DISTANCE_M: number = 60;

export function playEventName(context: common.Context): string {
  return `${context.applicationInfo.name}.PLAY_PLACE`;
}

export class HandsFree {
  private static context: common.Context | null = null;
  private static subscriber: commonEventManager.CommonEventSubscriber | null = null;
  private static player: NarratorPlayer = new NarratorPlayer();
  private static session: NarrationSession = new NarrationSession();
  private static currentId: string = '';
  private static played: string[] = [];

  /** Starts listening for "Rozpocznij" from notifications. */
  static async init(context: common.Context): Promise<void> {
    if (HandsFree.subscriber !== null) {
      return;
    }
    HandsFree.context = context;
    try {
      const subscriber = await commonEventManager.createSubscriber({ events: [playEventName(context)] });
      HandsFree.subscriber = subscriber;
      commonEventManager.subscribe(subscriber, (err: BusinessError, data: commonEventManager.CommonEventData) => {
        const params: Record<string, Object> = data?.parameters ?? {};
        const id: Object | undefined = params['placeId'];
        if (!err && typeof id === 'string') {
          HandsFree.playById(id);
        }
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'subscribe failed: %{public}s', JSON.stringify(e));
    }
  }

  static enabled(): boolean {
    return AppStorage.get<boolean>('handsFree') === true;
  }

  /** In hands-free mode: the nearest landmark within 60 m not told yet starts by itself. */
  static async checkArrival(queue: Place[], fix: GeoFix): Promise<void> {
    if (!HandsFree.enabled() || HandsFree.busy()) {
      return;
    }
    const near = queue
      .filter((p: Place) => !HandsFree.played.includes(p.id) && distanceM(fix, p) <= ARRIVAL_DISTANCE_M)
      .sort((a: Place, b: Place) => distanceM(fix, a) - distanceM(fix, b));
    if (near.length > 0) {
      await HandsFree.play(near[0]);
    }
  }

  static playById(id: string): void {
    const place = PlaceQueue.get(id) ?? SavedPlaces.get(id);
    if (place !== null) {
      HandsFree.play(place);
    }
  }

  static stop(): void {
    HandsFree.player.release();
    HandsFree.session.end();
    HandsFree.currentId = '';
    AppStorage.setOrCreate<boolean>('audioPlaying', false);
  }

  static reset(): void {
    HandsFree.stop();
    HandsFree.played = [];
  }

  /** The place screen is open or a story is playing: do not talk over it. */
  private static busy(): boolean {
    return AppStorage.get<boolean>('listening') === true || HandsFree.currentId.length > 0;
  }

  private static async play(place: Place): Promise<void> {
    const context = HandsFree.context;
    if (context === null || AppStorage.get<boolean>('listening') === true || HandsFree.currentId === place.id) {
      return;
    }
    HandsFree.stop();
    HandsFree.currentId = place.id;
    HandsFree.played.push(place.id);
    HandsFree.vibrate();
    const segment = await narrationWithVoice(place);
    if (segment.audioUrl === null || HandsFree.currentId !== place.id) {
      HandsFree.currentId = '';
      return;   // no voice (server or TTS down): nothing to hear, the notification still shows the place
    }
    const player = HandsFree.player;
    // the media session goes first: it is what allows playing while the phone is locked
    await HandsFree.session.start(context, place, segment.durationMs ?? 0, {
      play: () => {
        player.resume();
      },
      pause: () => {
        player.pause();
      },
      seek: (positionMs: number) => {
        player.seek(positionMs);
      },
    });
    let position = 0;
    let duration = segment.durationMs ?? 0;
    const listener: PlaybackListener = {
      onProgress: (positionMs: number, durationMs: number) => {
        position = positionMs;
        duration = durationMs > 0 ? durationMs : duration;
        if (duration > 0 && positionMs >= duration) {
          PlaceQueue.visited(place.id);   // told to the end: the next landmark takes its place
          HandsFree.stop();
        }
      },
      onStateChange: (playing: boolean) => {
        AppStorage.setOrCreate<boolean>('audioPlaying', playing);
        HandsFree.session.update(playing, position, duration);
      },
    };
    player.playUrl(segment.audioUrl, listener);
  }

  private static vibrate(): void {
    vibrator.startVibration({ type: 'time', duration: 400 }, { id: 0, usage: 'notification' }).catch(() => {
      // no vibrator: the sound alone has to do
    });
  }
}
