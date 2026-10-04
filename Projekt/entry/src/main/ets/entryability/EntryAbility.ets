import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { emitAppBackground, emitAppForeground, emitDebugAction } from '../platform/AppLifecycle';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  // `hdc shell aa start -a EntryAbility -b <bundle> --ps page debug [--ps room 1234]` opens the guide debug page
  private startPage: string = 'pages/StartPage';

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (want.parameters !== undefined && want.parameters['page'] === 'debug') {
      this.startPage = 'pages/GuideDebugPage';
      // `--ps room 1234`: start the simulated walk and join that room as FOLLOW (no typing on a watch)
      const room = want.parameters['room'];
      if (room !== undefined) {
        AppStorage.setOrCreate('debugJoinRoom', String(room));
      }
    }
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  // `aa start ... --ps action takeover` to a running app: a debug command (no reachable button on a watch)
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (want.parameters !== undefined && want.parameters['action'] !== undefined) {
      emitDebugAction(String(want.parameters['action']));
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Główny start aplikacji – ładuje ekran powitalny StartPage
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent(this.startPage, (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    emitAppForeground();
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    // one-time location grant: the walk pauses when the app leaves the foreground (#48)
    emitAppBackground();
  }
}