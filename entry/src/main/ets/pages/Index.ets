import { NarratorPlayer } from '../audio/NarratorPlayer';
import common from '@ohos.app.ability.common';

@Entry
@Component
struct StartPage {
  private player: NarratorPlayer = new NarratorPlayer();
  private context = getContext(this) as common.UIAbilityContext;

  build() {
    Row() {
      Column() {
        Text('Spacer z histori¹ - Spike DŸwiêku (P5)')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 20 })

        Button('Odtwórz testowy MP3')
          .fontSize(16)
          .onClick(() => {
            this.player.playRawFile(this.context, 'test.mp3');
          })
          .width('80%')
          .height(50)
      }
      .width('100%')
    }
    .height('100%')
  }
}
