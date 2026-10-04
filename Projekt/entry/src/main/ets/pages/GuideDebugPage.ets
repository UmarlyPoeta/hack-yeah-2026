import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { GeoFix } from '../model/GeoPoint';
import { Poi } from '../model/Poi';
import { Segment } from '../model/Segment';
import { parsePois, parseRoute, ParseResult } from '../data/FixtureParser';
import { LiveLocationProvider } from '../location/LiveLocationProvider';
import { LocationProvider } from '../location/LocationProvider';
import { RouteReplayProvider } from '../location/RouteReplayProvider';
import { VibratorHaptics } from '../platform/VibratorHaptics';
import { NarrationOutput } from '../viewmodel/WalkController';
import { WalkViewModel } from '../viewmodel/WalkViewModel';

// DEBUG page for the guide engine (P2): runs a full walk with the session (#48), the controls of #50,
// Live View (#54) and wrist cues (#52), before P5's WalkPage is wired (#49).
// Two sources: real GPS (asks "Allow this time only") or the bundled demo route at SPEED× (SYMULACJA).
// No voice here: text only, the planner estimates durations.

const SPEED: number = 10;

class TextOnlyOutput implements NarrationOutput {
  play(segment: Segment): void {
  }
  stop(): void {
  }
}

@Entry
@ComponentV2
struct GuideDebugPage {
  @Local vm: WalkViewModel = new WalkViewModel();
  @Local loadInfo: string = '';

  aboutToDisappear(): void {
    this.vm.stop();
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private readRaw(name: string): string {
    try {
      const bytes: Uint8Array = this.ctx().resourceManager.getRawFileContentSync(name);
      return util.TextDecoder.create('utf-8').decodeToString(bytes);
    } catch (e) {
      return '';   // the parser reports an empty file as an error on screen
    }
  }

  private start(simulated: boolean): void {
    const pois: ParseResult<Poi> = parsePois(this.readRaw('pois-krakow.json'));
    const route: ParseResult<GeoFix> = parseRoute(this.readRaw('demo-route-krakow.json'));
    this.loadInfo = pois.items.length + ' miejsc, ' + route.items.length + ' punktów trasy'
      + (pois.error !== null ? ' · błąd: ' + pois.error : '');
    const provider: LocationProvider = simulated ? new RouteReplayProvider(route.items, SPEED) : new LiveLocationProvider();
    this.vm.startWalk({
      pois: pois.items,
      interests: [],
      client: null,
      output: new TextOnlyOutput(),
      provider: provider,
      context: this.ctx(),
      haptics: new VibratorHaptics(),
      liveView: true
    });
  }

  @Builder
  row(label: string, value: string) {
    Row({ space: 6 }) {
      Text(label).fontSize(12).fontColor('#5B6672')
      Text(value).fontSize(13)
    }
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Text('Przewodnik: debug · ' + deviceInfo.deviceType).fontSize(20).fontWeight(FontWeight.Bold)
        if (this.vm.simulated) {
          Text('SYMULACJA · trasa demo ×' + SPEED + ' · bez głosu').fontSize(12).fontColor('#B35900')
            .fontWeight(FontWeight.Bold)
        }
        Row({ space: 8 }) {
          Button('Start: GPS').fontSize(12).onClick(() => this.start(false))
          Button('Start: symulacja').fontSize(12).onClick(() => this.start(true))
          Button('Stop').fontSize(12).onClick(() => this.vm.stop())
        }
        if (this.loadInfo.length > 0) {
          Text(this.loadInfo).fontSize(12).fontColor('#5B6672')
        }
        Column({ space: 2 }) {
          this.row('Sesja', this.vm.sessionState + (this.vm.sessionReason !== 'NONE' ? ' · ' + this.vm.sessionReason : ''))
          this.row('Rola', this.vm.role + (this.vm.peerConnected ? ' · połączony' : ''))
          this.row('Ruch', (this.vm.moving ? 'idzie' : 'stoi') + ' · opowiedziano: ' + this.vm.storiesTold
            + (this.vm.narrationPaused ? ' · NARRACJA WSTRZYMANA' : ''))
        }.alignItems(HorizontalAlign.Start).width('100%')
        if (this.vm.sessionState === 'PAUSED' || this.vm.sessionState === 'ERROR') {
          Button('Wznów spacer').fontSize(12).onClick(() => this.vm.resumeWalk())
        }
        Row({ space: 6 }) {
          Button(this.vm.narrationPaused ? 'Wznów' : 'Pauza').fontSize(12).onClick(() => {
            if (this.vm.narrationPaused) {
              this.vm.resumeNarration();
            } else {
              this.vm.pauseNarration();
            }
          })
          Button('Pomiń').fontSize(12).onClick(() => this.vm.skip())
          Button('Powtórz').fontSize(12).onClick(() => this.vm.replay())
        }
        Column({ space: 4 }) {
          Text('DALEJ').fontSize(11).fontColor('#5B6672')
          Text(this.vm.nextPoiName.length > 0 ? this.vm.nextPoiName : '—').fontSize(17).fontWeight(FontWeight.Medium)
          Text(this.vm.distanceM + ' m · ' + this.vm.etaSeconds + ' s · kierunek ' + this.vm.bearingAngle + '°')
            .fontSize(13)
          Text('Potem: ' + this.vm.laterStops.join(' → ')).fontSize(12).fontColor('#5B6672')
        }.alignItems(HorizontalAlign.Start).width('100%')
        Column({ space: 6 }) {
          Text(this.vm.segmentKind + (this.vm.poiName.length > 0 ? ' · ' + this.vm.poiName : '')
            + (this.vm.originLabel.length > 0 ? ' · ' + this.vm.originLabel : ''))
            .fontSize(12).fontColor('#2E6BD3')
          Text(this.vm.currentText).fontSize(16)
        }.alignItems(HorizontalAlign.Start).width('100%')
        .padding(12).borderRadius(8).backgroundColor('#F1F4F8')
        if (this.vm.deepDiveOfferId.length > 0) {
          Button('Opowiedz więcej o: ' + this.vm.deepDiveOfferName).onClick(() => this.vm.acceptDeepDive())
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding(deviceInfo.deviceType === 'wearable' ? 28 : 16)
      .width('100%')
    }
    .height('100%')
  }
}
