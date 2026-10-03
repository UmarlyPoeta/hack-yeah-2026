import { NarratorPlayer } from '../audio/NarratorPlayer';
import { Teleprompter } from '../components/Teleprompter';
import { RouteStrip } from '../components/RouteStrip';
import { Radar } from '../components/Radar';
import { SessionBadge } from '../components/SessionBadge';
import { DeepDiveSheet } from '../components/DeepDiveSheet';
import common from '@ohos.app.ability.common';
import router from '@ohos.router';
import { Eyebrow, Fonts, Palette } from '../common/Theme';

@Entry
@Component
struct WalkPage {
  private player: NarratorPlayer = new NarratorPlayer();

  @State currentText: string =
    'Zaczynamy spacer. Pierwszy przystanek: Barbakan w Krakowie, ok. 120 m przed nami.';

  @State poiName: string = 'Barbakan w Krakowie';
  @State segmentKind: string = 'WELCOME';
  @State nextPoiName: string = 'Brama Floriańska';
  @State distanceM: number = 120;
  @State etaSeconds: number = 90;
  @State sessionState: string = 'WALKING';
  @State bearingAngle: number = 45;
  @State isDeepDiveOpen: boolean = false;
  // mock until WalkViewModel (P2) provides the itinerary
  @State laterStops: string[] = ['Kościół Mariacki', 'Sukiennice', 'Collegium Maius', 'Wawel'];

  // Leaving the walk page (button or system back) must stop the narration.
  aboutToDisappear(): void {
    this.player.release();
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Eyebrow('SPACER · KRAKÓW')
          Blank()
          SessionBadge({ sessionState: this.sessionState })
        }
        .width('100%')
        .margin({ top: 8 })

        Row() {
          RouteStrip({
            nextPoiName: this.nextPoiName,
            distanceM: this.distanceM,
            etaSeconds: this.etaSeconds
          })
            .layoutWeight(1)
          Radar({
            poiName: this.nextPoiName,
            distanceM: this.distanceM,
            bearingAngle: this.bearingAngle
          })
            .margin({ left: 16 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .margin({ top: 28 })

        Column() {
          Eyebrow('DALEJ NA TRASIE')
          Text(this.laterStops.join('  ·  '))
            .fontFamily(Fonts.ITALIC)
            .fontSize(17)
            .lineHeight(25)
            .fontColor(Palette.INK_SOFT)
            .margin({ top: 6 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 16 })
        .margin({ top: 22 })
        .border({ width: { top: 1 }, color: Palette.RULE })

        Blank()

        Teleprompter({
          currentText: this.currentText,
          poiName: this.poiName,
          segmentKind: this.segmentKind,
          onPlayClick: () => {
            const context = getContext(this) as common.UIAbilityContext;
            this.player.playRawFile(context, 'test.mp3');
          }
        })

        Button({ type: ButtonType.Normal }) {
          Row() {
            Text('Opowiedz więcej o tym miejscu')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Palette.INK)
            Blank()
            Text('↑')
              .fontSize(17)
              .fontColor(Palette.INK)
          }
          .width('100%')
          .padding({ left: 20, right: 20 })
        }
        .width('100%')
        .height(52)
        .borderRadius(14)
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: Palette.INK, radius: 14 })
        .margin({ top: 14 })
        .onClick(() => {
          this.isDeepDiveOpen = true;
        })

        Text('Zakończ spacer')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Palette.BRICK)
          .padding(12)
          .margin({ top: 10, bottom: 8 })
          .onClick(() => {
            this.player.release();
            router.back();
          })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 24, right: 24 })
      .backgroundColor(Palette.PAPER)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      DeepDiveSheet({
        isShown: $isDeepDiveOpen,
        title: this.poiName,
        content: 'Barbakan (zwany też Rondlem) – barbakan, najbardziej wysunięta na północ część fortyfikacji ' +
          'miejskich Krakowa. Znajduje się na Plantach, przed Bramą Floriańską, po południowej stronie ul. Basztowej.'
      })
    }
    .width('100%')
    .height('100%')
  }
}
