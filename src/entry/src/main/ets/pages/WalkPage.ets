import { NarratorPlayer } from '../audio/NarratorPlayer';
import common from '@ohos.app.ability.common';
import router from '@ohos.router';

@Entry
@Component
struct WalkPage {
  private player: NarratorPlayer = new NarratorPlayer();
  @State currentText: string = 'Zaczynamy spacer. Pierwszy przystanek: Barbakan w Krakowie, ok. 120 m przed nami.';
  @State poiName: string = 'Barbakan w Krakowie';

  build() {
    Column() {
      // Górny pasek
      Row() {
        Text('Spacer z historią')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.Black)
        Blank()
        Text('WALKING')
          .fontSize(12)
          .fontColor(Color.Green)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)

      // Główna karta z treścią
      Column() {
        Text(this.poiName)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.Blue)
          .margin({ bottom: 12 })

        Text(this.currentText)
          .fontSize(16)
          .fontColor('#666666')
          .lineHeight(24)
          .margin({ bottom: 20 })

        Button('Odsłuchaj narrację (Test MP3)')
          .onClick(() => {
            let context = getContext(this) as common.UIAbilityContext;
            this.player.playRawFile(context, 'test.mp3');
          })
          .width('100%')
          .height(45)
          .backgroundColor('#007DFF')
          .fontColor(Color.White)
      }
      .width('90%')
      .padding(20)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .margin({ top: 40 })

      Blank()

      // Przycisk wyjścia
      Button('Zakończ spacer')
        .backgroundColor('#FF4D4F')
        .fontColor(Color.White)
        .width('80%')
        .height(45)
        .margin({ bottom: 30 })
        .onClick(() => {
          router.back();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#EFEFEF')
    .alignItems(HorizontalAlign.Center)
  }
}