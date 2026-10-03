import { NarratorPlayer } from '../audio/NarratorPlayer';
import { Teleprompter } from '../components/Teleprompter';
import common from '@ohos.app.ability.common';
import router from '@ohos.router';

@Entry
@Component
struct WalkPage {
  private player: NarratorPlayer = new NarratorPlayer();
  @State currentText: string = 'Zaczynamy spacer. Pierwszy przystanek: Barbakan w Krakowie, ok. 120 m przed nami.';
  @State poiName: string = 'Barbakan w Krakowie';
  @State segmentKind: string = 'WELCOME';

  build() {
    Column() {
      // Górny pasek statusu sesji
      Row() {
        Text('Spacer z historią')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
        Blank()
        Text('🟢 WALKING')
          .fontSize(12)
          .fontColor(Color.Green)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)

      Blank()

      // Główny teleprompter z treścią narracji
      Teleprompter({
        currentText: this.currentText,
        poiName: this.poiName,
        segmentKind: this.segmentKind,
        onPlayClick: () => {
          let context = getContext(this) as common.UIAbilityContext;
          this.player.playRawFile(context, 'test.mp3');
        }
      })

      Blank()

      // Przycisk wyjścia / powrotu
      Button('Zakończ spacer')
        .backgroundColor('#FF4D4F')
        .fontColor(Color.White)
        .width('80%')
        .height(45)
        .margin({ bottom: 20 })
        .onClick(() => {
          router.back();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}