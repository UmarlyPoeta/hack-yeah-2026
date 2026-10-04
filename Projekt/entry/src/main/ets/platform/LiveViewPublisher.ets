import { liveViewManager } from '@kit.LiveViewKit';
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { WalkUiState } from '../viewmodel/WalkController';

// The next stop in the status bar and on the lock screen (issue #54), with the navigation template.
// Phone only: the watch has no Live View service (spike: SystemCapability.LiveView.LiveViewService).
// Live Views can only be started while the app is in the foreground; updates keep it current.

const LIVE_VIEW_ID: number = 1;
const MIN_UPDATE_MS: number = 10000;

export class LiveViewPublisher {
  private context: common.UIAbilityContext;
  private agent: WantAgent | null = null;
  private started: boolean = false;
  private sequence: number = 0;
  private lastKey: string = '';
  private lastUpdateT: number = 0;
  private busy: boolean = false;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  static supported(): boolean {
    return canIUse('SystemCapability.LiveView.LiveViewService');
  }

  // Called on every state change; sends only when something visible changed, or every 10 s.
  update(s: WalkUiState, paused: boolean): void {
    if (!LiveViewPublisher.supported() || this.busy) {
      return;
    }
    const icon = s.bearingAngle < -30 ? 'lv_left.png' : (s.bearingAngle > 30 ? 'lv_right.png' : 'lv_ahead.png');
    const key = s.nextPoiName + '|' + icon + '|' + paused;
    const now = Date.now();
    if (this.started && key === this.lastKey && now - this.lastUpdateT < MIN_UPDATE_MS) {
      return;
    }
    this.lastKey = key;
    this.lastUpdateT = now;
    this.busy = true;
    this.send(s, paused, icon).finally(() => {
      this.busy = false;
    });
  }

  async stop(): Promise<void> {
    if (!LiveViewPublisher.supported() || !this.started) {
      return;
    }
    try {
      await liveViewManager.stopLiveView(this.build('Koniec spaceru', 'Dziękujemy za wspólny spacer', 'lv_ahead.png'));
    } catch (e) {
      console.error('live view stop failed: ' + (e as BusinessError).code);
    }
    this.started = false;
  }

  private async send(s: WalkUiState, paused: boolean, icon: string): Promise<void> {
    let title = s.nextPoiName.length > 0 ? s.nextPoiName : 'Spacer z historią';
    let content = s.nextPoiName.length > 0 ? s.distanceM + ' m · ' + this.eta(s.etaSeconds) : 'Idziemy dalej';
    if (paused) {
      title = 'Spacer wstrzymany';
      content = 'Otwórz aplikację, aby kontynuować';
    }
    try {
      if (this.agent === null) {
        this.agent = await this.makeAgent();
      }
      if (!this.started) {
        if (!(await liveViewManager.isLiveViewEnabled())) {
          return;                                  // switched off by the user in Settings: respect it
        }
        const r = await liveViewManager.startLiveView(this.build(title, content, icon));
        this.started = r.resultCode === 0;
      } else {
        await liveViewManager.updateLiveView(this.build(title, content, icon));
      }
    } catch (e) {
      // the walk must go on without the Live View
      console.error('live view failed: ' + (e as BusinessError).code + ' ' + (e as BusinessError).message);
    }
  }

  private build(title: string, content: string, icon: string): liveViewManager.LiveView {
    this.sequence++;
    const lv: liveViewManager.LiveView = {
      id: LIVE_VIEW_ID,
      event: 'NAVIGATION',
      sequence: this.sequence,
      liveViewData: {
        primary: {
          title: title,
          content: [{ text: content }],
          keepTime: 15,
          clickAction: this.agent !== null ? this.agent : undefined,
          layoutData: {
            layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_NAVIGATION,
            currentNavigationIcon: icon,
            navigationIcons: ['lv_left.png', 'lv_ahead.png', 'lv_right.png']
          }
        }
      }
    };
    return lv;
  }

  private eta(seconds: number): string {
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return m + ':' + (s < 10 ? '0' : '') + s;
  }

  private async makeAgent(): Promise<WantAgent> {
    const info: wantAgent.WantAgentInfo = {
      wants: [{ bundleName: this.context.abilityInfo.bundleName, abilityName: 'EntryAbility' }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return wantAgent.getWantAgent(info);
  }
}
