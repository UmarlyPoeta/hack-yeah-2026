// The user's position for picking nearby landmarks: one-off fixes, not continuous tracking.
// AppStorage: 'locationAuthorized' (boolean), 'userLat' / 'userLon' (number, 0 until the first fix).
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { geoLocationManager } from '@kit.LocationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GeoFix } from '../model/GeoPoint';

const DOMAIN: number = 0x0000;
const TAG: string = 'UserLocation';
const PERMISSIONS: Permissions[] = ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION'];
const FIX_TIMEOUT_MS: number = 10000;

export class UserLocation {
  /** Shows the system dialog when needed; true when at least approximate location is granted. */
  static async requestPermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, PERMISSIONS);
      const granted = result.authResults.some((r: number) => r === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
      AppStorage.setOrCreate<boolean>('locationAuthorized', granted);
      return granted;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'permission request failed: %{public}s', JSON.stringify(e));
      AppStorage.setOrCreate<boolean>('locationAuthorized', false);
      return false;
    }
  }

  /** Current position, else the last known one, else null. Never rejects. */
  static async current(): Promise<GeoFix | null> {
    try {
      const request: geoLocationManager.SingleLocationRequest = {
        locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED,
        locatingTimeoutMs: FIX_TIMEOUT_MS,
      };
      return UserLocation.remember(await geoLocationManager.getCurrentLocation(request));
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'current location failed: %{public}s', JSON.stringify(e));
    }
    try {
      return UserLocation.remember(geoLocationManager.getLastLocation());
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'no last location: %{public}s', JSON.stringify(e));
      return null;
    }
  }

  /** Last position this session or from a previous one (restored by the queue), else null. */
  static known(): GeoFix | null {
    const lat = AppStorage.get<number>('userLat') ?? 0;
    const lon = AppStorage.get<number>('userLon') ?? 0;
    if (lat === 0 && lon === 0) {
      return null;
    }
    const fix: GeoFix = { lat: lat, lon: lon, accuracyM: 100, t: Date.now() };
    return fix;
  }

  private static remember(loc: geoLocationManager.Location): GeoFix {
    AppStorage.setOrCreate<number>('userLat', loc.latitude);
    AppStorage.setOrCreate<number>('userLon', loc.longitude);
    const fix: GeoFix = { lat: loc.latitude, lon: loc.longitude, accuracyM: loc.accuracy, t: Date.now() };
    return fix;
  }
}
