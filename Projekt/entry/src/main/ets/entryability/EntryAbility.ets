import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { PlaceQueue } from '../store/PlaceQueue';
import { SavedPlaces } from '../store/SavedPlaces';
import { Services } from '../store/Services';
import { Settings } from '../store/Settings';
import { CityInfo } from '../store/CityInfo';
import { Guide } from '../store/Guide';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    this.takePlaceId(want);
  }

  // tapping the notification while the app is running
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.takePlaceId(want);
  }

  /** Notification "Rozpocznij": MainPage opens AppStorage 'openPlaceId'. */
  private takePlaceId(want: Want): void {
    let id = want.parameters?.placeId;
    // home screen card: postCardAction 'router' delivers its params as a JSON string
    const cardParams = want.parameters?.params;
    if (id === undefined && typeof cardParams === 'string') {
      try {
        id = (JSON.parse(cardParams) as Record<string, string>)['placeId'];
      } catch (e) {
        id = undefined;
      }
    }
    if (typeof id === 'string' && id.length > 0) {
      AppStorage.setOrCreate<string>('openPlaceId', id);
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // First launch: OnboardingPage, afterwards the tabs (MainPage). The saved landmark queue is restored
    // before the first frame. Full-screen layout so photos and maps go under the status bar.
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');
    Services.init(this.context);
    Settings.init(this.context);
    PlaceQueue.init(this.context);
    SavedPlaces.init(this.context);
    CityInfo.init(this.context);

    windowStage.loadContent(Settings.onboarded() ? 'pages/MainPage' : 'pages/OnboardingPage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      this.useFullScreenLayout(windowStage.getMainWindowSync());
    });
  }

  // Screens read AppStorage 'topInset' / 'bottomInset' (vp) to keep buttons clear of the status bar
  // and the navigation indicator.
  private useFullScreenLayout(win: window.Window): void {
    try {
      win.setWindowLayoutFullScreen(true);
      const ui = win.getUIContext();
      const top = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM).topRect.height;
      const bottom = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR).bottomRect.height;
      AppStorage.setOrCreate<number>('topInset', ui.px2vp(top));
      AppStorage.setOrCreate<number>('bottomInset', ui.px2vp(bottom));
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Full-screen layout failed: %{public}s', JSON.stringify(err));
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    Guide.enterForeground();
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    Guide.enterBackground();
  }
}