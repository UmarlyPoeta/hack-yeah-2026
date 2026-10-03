import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    this.restoreContinuation(want, launchParam);
    // SPIKE: let the system offer this walk on another device of the same account
    this.context.setMissionContinueState(AbilityConstant.ContinueState.ACTIVE, () => {});
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.restoreContinuation(want, launchParam);
  }

  // SPIKE: source side of App Continuation; only essential, synchronous data
  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    wantParam['spikeProgress'] = 'spokenStops=3;lastStop=plwiki:19010;t=' + Date.now();
    hilog.info(DOMAIN, 'testTag', 'onContinue: sending progress');
    return AbilityConstant.OnContinueResult.AGREE;
  }

  private restoreContinuation(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (launchParam.launchReason === AbilityConstant.LaunchReason.CONTINUATION && want.parameters !== undefined) {
      AppStorage.setOrCreate('continuationData', String(want.parameters['spikeProgress']));
      this.context.restoreWindowStage(new LocalStorage());
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Główny start aplikacji – ładuje ekran powitalny StartPage
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // SPIKE branch: start on the feature test page (main keeps StartPage)
    windowStage.loadContent('pages/SpikePage', (err) => {
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
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}