// "Zabytek w pobliżu" notification: photo and name; tapping it opens the place, "Rozpocznij" plays the story
// on the phone right away (HandsFree), also when pressed on a paired watch.
// At most one notification every 2 minutes; each new one replaces the previous (same id), and it stays
// in the notification centre (isOngoing) until the next one or until the user opens the app.
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { distanceM } from '../guide/geo';
import { GeoFix } from '../model/GeoPoint';
import { distanceLabel, Place, shortName } from '../model/Place';
import { playEventName } from './HandsFree';

const DOMAIN: number = 0x0000;
const TAG: string = 'Notifier';
const NOTIFICATION_ID: number = 1001;
export const MIN_INTERVAL_MS: number = 120000;
const MAX_NOTIFIED: number = 100;

export class Notifier {
  private static lastAt: number = 0;
  private static notified: string[] = [];

  /** System dialog "allow notifications"; does nothing when already allowed. */
  static async enable(context: common.UIAbilityContext): Promise<void> {
    try {
      await notificationManager.requestEnableNotification(context);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'notifications not enabled: %{public}s', JSON.stringify(e));
    }
  }

  /** Notifies about the nearest queued place not announced yet, unless one was sent in the last 2 minutes. */
  static async maybeNotify(context: common.Context, queue: Place[], fix: GeoFix | null): Promise<void> {
    const now = Date.now();
    if (now - Notifier.lastAt < MIN_INTERVAL_MS || AppStorage.get<boolean>('listening') === true) {
      return;
    }
    const fresh = queue.filter((p: Place) => !Notifier.notified.includes(p.id));
    if (fresh.length === 0) {
      return;
    }
    if (fix !== null) {
      fresh.sort((a: Place, b: Place) => distanceM(fix, a) - distanceM(fix, b));
    }
    const place = fresh[0];
    Notifier.lastAt = now;
    Notifier.notified.push(place.id);
    if (Notifier.notified.length > MAX_NOTIFIED) {
      Notifier.notified = Notifier.notified.slice(-MAX_NOTIFIED);
    }
    await Notifier.publish(context, place, fix);
  }

  static async cancel(): Promise<void> {
    try {
      await notificationManager.cancel(NOTIFICATION_ID);
    } catch (e) {
      // nothing shown
    }
  }

  static reset(): void {
    Notifier.lastAt = 0;
    Notifier.notified = [];
    Notifier.cancel();
  }

  private static async publish(context: common.Context, place: Place, fix: GeoFix | null): Promise<void> {
    try {
      const agent = await Notifier.openPlaceAgent(context, place.id);
      const play = await Notifier.playAgent(context, place.id);
      const title = shortName(place);
      const text = fix !== null ? `${distanceLabel(distanceM(fix, place))} od ciebie` : 'Zabytek w pobliżu';
      const picture = await Notifier.pixelMap(place.imageFile);
      const content: notificationManager.NotificationContent = picture !== null ? {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_PICTURE,
        picture: {
          title: title,
          text: text,
          briefText: 'tour',
          expandedTitle: title,
          picture: picture,
        },
      } : {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: title, text: text },
      };
      const request: notificationManager.NotificationRequest = {
        id: NOTIFICATION_ID,
        content: content,
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: true,
        tapDismissed: true,
        wantAgent: agent,
        // "Rozpocznij" plays on the phone without opening the app, so it works from a watch or the lock screen
        actionButtons: [{ title: 'Rozpocznij', wantAgent: play }],
        // shown on and operable from a paired watch (relayed by the system, e.g. Huawei Health)
        distributedOption: {
          isDistributed: true,
          supportDisplayDevices: ['phone', 'wearable', 'liteWearable'],
          supportOperateDevices: ['phone', 'wearable', 'liteWearable'],
        },
      };
      if (picture !== null) {
        request.largeIcon = picture;
      }
      await notificationManager.publish(request);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'publish failed: %{public}s', JSON.stringify(e));
    }
  }

  /** Opens EntryAbility with { placeId }; EntryAbility hands it to MainPage through AppStorage 'openPlaceId'. */
  private static async openPlaceAgent(context: common.Context, placeId: string): Promise<WantAgent> {
    const info: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: context.applicationInfo.name,
        abilityName: 'EntryAbility',
        parameters: { placeId: placeId },
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 1,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    };
    return wantAgent.getWantAgent(info);
  }

  /** Common event received by HandsFree: the phone starts the story, the screen stays as it is. */
  private static async playAgent(context: common.Context, placeId: string): Promise<WantAgent> {
    const info: wantAgent.WantAgentInfo = {
      wants: [{ action: playEventName(context), parameters: { placeId: placeId } }],
      actionType: wantAgent.OperationType.SEND_COMMON_EVENT,
      requestCode: 4,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    };
    return wantAgent.getWantAgent(info);
  }

  private static async pixelMap(path: string): Promise<image.PixelMap | null> {
    if (path.length === 0) {
      return null;
    }
    try {
      const source = image.createImageSource(path);
      const map = await source.createPixelMap({ desiredSize: { width: 512, height: 288 } });
      source.release();
      return map;
    } catch (e) {
      return null;
    }
  }
}
