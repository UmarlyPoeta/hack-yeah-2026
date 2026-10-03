import { util } from '@kit.ArkTS';
import { GeoFix } from '../model/GeoPoint';
import { Poi } from '../model/Poi';
import { Segment } from '../model/Segment';
import { parsePois, parseRoute, ParseResult } from '../data/FixtureParser';
import { Clock, NarrationOutput } from '../viewmodel/WalkController';
import { WalkViewModel } from '../viewmodel/WalkViewModel';

// DEBUG ONLY, clearly labelled as a simulation: replays the bundled demo route at SPEED× so the
// guide engine can be checked on the emulator before LocationProvider (P1) and the real
// screens (P5) are wired in. Offline: templates only, text without voice.

const SPEED: number = 10;

class SimClock implements Clock {
  private startReal: number = Date.now();
  now(): number {
    return (Date.now() - this.startReal) * SPEED;
  }
}

class TextOnlyOutput implements NarrationOutput {
  play(segment: Segment): void {
    // no audio in the debug replay: the page shows the text, the planner estimates the duration
  }
  stop(): void {
  }
}

@Entry
@ComponentV2
struct GuideDebugPage {
  @Local vm: WalkViewModel = new WalkViewModel();
  @Local simSeconds: number = 0;
  @Local loadInfo: string = '';
  private feedTimer: number = -1;

  aboutToDisappear(): void {
    this.stopReplay();
  }

  private readRaw(name: string): string {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return '';
    }
    try {
      const bytes: Uint8Array = ctx.resourceManager.getRawFileContentSync(name);
      return util.TextDecoder.create('utf-8').decodeToString(bytes);
    } catch (e) {
      return '';   // the parser reports an empty file as an error on screen
    }
  }

  private startReplay(): void {
    this.stopReplay();
    const pois: ParseResult<Poi> = parsePois(this.readRaw('pois-krakow.json'));
    const route: ParseResult<GeoFix> = parseRoute(this.readRaw('demo-route-krakow.json'));
    this.loadInfo = pois.items.length + ' miejsc, ' + route.items.length + ' punktów trasy'
      + (pois.error !== null ? ' · błąd: ' + pois.error : '');
    const clock = new SimClock();
    this.vm.start(pois.items, [], null, new TextOnlyOutput(), clock, 1000 / SPEED);
    let next = 0;
    this.feedTimer = setInterval(() => {
      const now = clock.now();
      this.simSeconds = Math.round(now / 1000);
      while (next < route.items.length && route.items[next].t <= now) {
        this.vm.onFix(route.items[next]);
        next++;
      }
      if (next >= route.items.length && now > route.items[route.items.length - 1].t + 60000) {
        this.stopReplay();
      }
    }, 100);
  }

  private stopReplay(): void {
    if (this.feedTimer >= 0) {
      clearInterval(this.feedTimer);
      this.feedTimer = -1;
    }
    this.vm.stop();
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('SYMULACJA · trasa demo ×' + SPEED + ' · bez GPS, bez głosu')
          .fontSize(12).fontColor('#B35900').fontWeight(FontWeight.Bold)
        Text('Przewodnik: debug').fontSize(22).fontWeight(FontWeight.Bold)
        Row({ space: 12 }) {
          Button(this.vm.active ? 'Zatrzymaj' : 'Start spaceru').onClick(() => {
            if (this.vm.active) {
              this.stopReplay();
            } else {
              this.startReplay();
            }
          })
          Text('t = ' + this.simSeconds + ' s · ' + (this.vm.moving ? 'idzie' : 'stoi')
            + ' · opowiedziano: ' + this.vm.storiesTold).fontSize(13)
        }
        if (this.loadInfo.length > 0) {
          Text(this.loadInfo).fontSize(12).fontColor('#5B6672')
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
      .padding(16)
      .width('100%')
    }
    .height('100%')
  }
}
