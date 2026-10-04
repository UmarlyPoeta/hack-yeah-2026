// The app's heartbeat: every 2 minutes (and when asked) it takes the user's position, refills the landmark
// queue, updates the town card and may send the "Zabytek w pobliżu" notification.
// In the background it keeps running as a location continuous task, which also shows the system's
// "tour działa w tle" notification.
import { common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Place } from '../model/Place';
import { CityInfo } from './CityInfo';
import { preloadNarration } from './Narration';
import { MIN_INTERVAL_MS, Notifier } from './Notifier';
import { PlaceQueue } from './PlaceQueue';
import { UserLocation } from './UserLocation';
import { Widgets } from './Widgets';

const DOMAIN: number = 0x0000;
const TAG: string = 'Guide';

export class Guide {
  private static context: common.UIAbilityContext | null = null;
  private static timer: number = -1;
  private static background: boolean = false;

  static start(context: common.UIAbilityContext): void {
    Guide.context = context;
    if (Guide.timer === -1) {
      Guide.timer = setInterval(() => Guide.refresh(), MIN_INTERVAL_MS);
    }
    Guide.refresh();
  }

  static stop(): void {
    clearInterval(Guide.timer);
    Guide.timer = -1;
  }

  static async refresh(): Promise<void> {
    const context = Guide.context;
    if (context === null) {
      return;
    }
    const fix = (await UserLocation.current()) ?? UserLocation.known();
    if (fix === null) {
      return;
    }
    CityInfo.update(fix);
    await PlaceQueue.refill(fix);
    preloadNarration(AppStorage.get<Place[]>('queue') ?? []);
    Widgets.update(context);
    await Notifier.maybeNotify(context, AppStorage.get<Place[]>('queue') ?? [], fix);
  }

  /** App went to the background: keep the heartbeat alive (needs the location permission). */
  static async enterBackground(): Promise<void> {
    const context = Guide.context;
    if (context === null || Guide.timer === -1 || Guide.background ||
      (AppStorage.get<boolean>('locationAuthorized') !== true && AppStorage.get<boolean>('audioPlaying') !== true)) {
      return;
    }
    try {
      const agent = await wantAgent.getWantAgent({
        wants: [{ bundleName: context.applicationInfo.name, abilityName: 'EntryAbility' }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 2,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      });
      // narration playing (with its media session) keeps sounding behind the lock screen
      const modes: string[] = AppStorage.get<boolean>('audioPlaying') === true ? ['location', 'audioPlayback'] : ['location'];
      await backgroundTaskManager.startBackgroundRunning(context, modes, agent);
      Guide.background = true;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'background running refused: %{public}s', JSON.stringify(e));
    }
  }

  static async enterForeground(): Promise<void> {
    if (!Guide.background || Guide.context === null) {
      return;
    }
    Guide.background = false;
    try {
      await backgroundTaskManager.stopBackgroundRunning(Guide.context);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'stop background running: %{public}s', JSON.stringify(e));
    }
  }
}
