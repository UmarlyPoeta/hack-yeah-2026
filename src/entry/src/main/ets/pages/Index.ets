import { NarratorPlayer } from '../audio/NarratorPlayer';
import common from '@ohos.app.ability.common';

@Entry
@Component
struct Index {
  private player: NarratorPlayer = new NarratorPlayer();

  build() {
    Row() {
      Column() {
        Text('Spacer z historią - Spike Dźwięku (P5)')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 20 })

        Button('Odtwórz testowy MP3')
          .fontSize(16)
          .onClick(() => {
            let context = getContext(this) as common.UIAbilityContext;
            this.player.playRawFile(context, 'test.mp3');
          })
          .width('80%')
          .height(50)
      }
      .width('100%')
    }
    .height('100%')
  }
}