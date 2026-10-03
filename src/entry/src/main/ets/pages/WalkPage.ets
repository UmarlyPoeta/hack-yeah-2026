import { NarratorPlayer } from '../audio/NarratorPlayer';
import { Teleprompter } from '../components/Teleprompter';
import { RouteStrip } from '../components/RouteStrip';
import { Radar } from '../components/Radar';
import { SessionBadge } from '../components/SessionBadge';
import { DeepDiveSheet } from '../components/DeepDiveSheet';
import common from '@ohos.app.ability.common';
import router from '@ohos.router';

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

  // Leaving the walk page (button or system back) must stop the narration.
  aboutToDisappear(): void {
    this.player.release();
  }

  build() {
    Stack() {
      Column() {

        // Górny pasek statusu z komponentem SessionBadge
        Row() {
          Text('Spacer z historią')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.Black)

          Blank()

          SessionBadge({
            sessionState: this.sessionState
          })
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Color.White)

        // Pasek trasy
        RouteStrip({
          nextPoiName: this.nextPoiName,
          distanceM: this.distanceM,
          etaSeconds: this.etaSeconds
        })
          .margin({ top: 12 })

        // Radar kierunkowy
        Radar({
          poiName: this.nextPoiName,
          distanceM: this.distanceM,
          bearingAngle: this.bearingAngle
        })
          .margin({ top: 8 })

        Blank()

        // Główny teleprompter z odtwarzaczem
        Teleprompter({
          currentText: this.currentText,
          poiName: this.poiName,
          segmentKind: this.segmentKind,

          onPlayClick: () => {
            let context = getContext(this) as common.UIAbilityContext;

            this.player.playRawFile(
              context,
              'test.mp3'
            );
          }
        })

        // Przycisk otwierający Deep Dive
        Button('Opowiedz więcej (Deep Dive)')
          .width('90%')
          .height(40)
          .margin({ top: 16 })
          .backgroundColor('#52C41A')
          .fontColor(Color.White)
          .onClick(() => {
            this.isDeepDiveOpen = true;
          })

        Blank()

        // Przycisk wyjścia
        Button('Zakończ spacer')
          .backgroundColor('#FF4D4F')
          .fontColor(Color.White)
          .width('80%')
          .height(45)
          .margin({ bottom: 30 })
          .onClick(() => {
            this.player.release();
            router.back();
          })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#EFEFEF')
      .alignItems(HorizontalAlign.Center)

      // Nakładka Deep Dive
      DeepDiveSheet({
        isShown: $isDeepDiveOpen,
        title: this.poiName,
        content:
        'Barbakan w Krakowie – historyczny barbakan, zachowany w świetnym stanie bastion obronny będący dawniej częścią murów miejskich Krakowa. Wybudowany pod koniec XV wieku...'
      })
    }
    .width('100%')
    .height('100%')
  }
}