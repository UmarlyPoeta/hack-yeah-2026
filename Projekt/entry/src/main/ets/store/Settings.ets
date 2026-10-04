// First-run state and interests, kept in Preferences so the app remembers them between launches.
// AppStorage: 'interests' (string[], Interest values).
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Interest } from '../model/Segment';

const KEY_ONBOARDED: string = 'onboarded';
const KEY_INTERESTS: string = 'interests';

export class Settings {
  private static prefs: preferences.Preferences | null = null;

  static init(context: common.Context): void {
    if (Settings.prefs === null) {
      Settings.prefs = preferences.getPreferencesSync(context, { name: 'tour' });
    }
    AppStorage.setOrCreate<string[]>('interests', Settings.interests());
  }

  static onboarded(): boolean {
    return Settings.prefs?.getSync(KEY_ONBOARDED, false) as boolean ?? false;
  }

  static interests(): string[] {
    return Settings.prefs?.getSync(KEY_INTERESTS, [] as string[]) as string[] ?? [];
  }

  static interestList(): Interest[] {
    return Settings.interests().map((i: string) => i as Interest);
  }

  static setInterests(interests: string[]): void {
    Settings.prefs?.putSync(KEY_INTERESTS, interests);
    Settings.prefs?.flushSync();
    AppStorage.setOrCreate<string[]>('interests', interests);
  }

  static finishOnboarding(): void {
    Settings.prefs?.putSync(KEY_ONBOARDED, true);
    Settings.prefs?.flushSync();
  }
}
