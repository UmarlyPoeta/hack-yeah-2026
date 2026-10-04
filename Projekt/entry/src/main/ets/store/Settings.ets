// First-run state and interests, kept in Preferences so the app remembers them between launches.
// AppStorage: 'interests' (string[], Interest values).
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { API_BASE_URL } from '../data/ApiConfig';
import { Interest } from '../model/Segment';

const KEY_ONBOARDED: string = 'onboarded';
const KEY_INTERESTS: string = 'interests';
const KEY_HANDS_FREE: string = 'handsFree';
const KEY_SERVER_URL: string = 'serverUrl';

export class Settings {
  private static prefs: preferences.Preferences | null = null;

  static init(context: common.Context): void {
    if (Settings.prefs === null) {
      Settings.prefs = preferences.getPreferencesSync(context, { name: 'tour' });
    }
    AppStorage.setOrCreate<string[]>('interests', Settings.interests());
    AppStorage.setOrCreate<boolean>('handsFree', Settings.prefs?.getSync(KEY_HANDS_FREE, false) as boolean ?? false);
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

  /** Server address set on the phone ("Moje" > Serwer), so a phone outside the emulator can use a tunnel or
   * the laptop's LAN address without a new build. */
  static serverUrl(): string {
    const url = Settings.prefs?.getSync(KEY_SERVER_URL, '') as string ?? '';
    return url.length > 0 ? url : API_BASE_URL;
  }

  static setServerUrl(url: string): void {
    Settings.prefs?.putSync(KEY_SERVER_URL, url);
    Settings.prefs?.flushSync();
  }

  /** "Tryb bez patrzenia": off unless someone switches it on in "Moje". */
  static setHandsFree(on: boolean): void {
    Settings.prefs?.putSync(KEY_HANDS_FREE, on);
    Settings.prefs?.flushSync();
    AppStorage.setOrCreate<boolean>('handsFree', on);
  }

  /** Back to the first launch: onboarding and interests are asked again. */
  static reset(): void {
    const server = Settings.prefs?.getSync(KEY_SERVER_URL, '') as string ?? '';   // a reset keeps the server address
    Settings.prefs?.clearSync();
    Settings.prefs?.putSync(KEY_SERVER_URL, server);
    Settings.prefs?.flushSync();
    AppStorage.setOrCreate<string[]>('interests', []);
    AppStorage.setOrCreate<boolean>('handsFree', false);
  }

  static finishOnboarding(): void {
    Settings.prefs?.putSync(KEY_ONBOARDED, true);
    Settings.prefs?.flushSync();
  }
}
