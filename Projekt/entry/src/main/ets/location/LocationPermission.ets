import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

// Asks for location with the system dialog. HarmonyOS 6.1 offers "Allow this time only", which is what
// the walk needs: the grant ends with the walk. LocationButton is not in the public 6.1.1 SDK (spike #48).
export async function requestLocationOnce(context: common.UIAbilityContext): Promise<boolean> {
  try {
    const atManager = abilityAccessCtrl.createAtManager();
    const result = await atManager.requestPermissionsFromUser(context,
      ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION']);
    // approximate location is enough to start; precise improves the guide
    return result.authResults.length > 0 && result.authResults[0] === 0;
  } catch (e) {
    const err = e as BusinessError;
    console.error('location permission request failed: ' + err.code + ' ' + err.message);
    return false;
  }
}
