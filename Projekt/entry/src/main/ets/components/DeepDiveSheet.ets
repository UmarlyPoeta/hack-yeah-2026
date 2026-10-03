import { Eyebrow, Fonts, Motion, Palette } from '../common/Theme';

@Component
export struct DeepDiveSheet {
  @Link isShown: boolean;
  @Prop title: string;
  @Prop content: string;

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.isShown) {
        // scrim: tap outside closes the sheet
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Palette.SCRIM)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .onClick(() => {
            this.isShown = false;
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 300, curve: Curve.EaseOut }))
      }

      if (this.isShown) {
        Column() {
          Row()
            .width(36)
            .height(4)
            .backgroundColor(Palette.RULE)
            .borderRadius(2)
            .margin({ top: 10, bottom: 22 })

          Row() {
            Eyebrow('OPOWIEŚĆ', Palette.BRICK)
            Blank()
            Text('Zamknij')
              .fontSize(14)
              .fontColor(Palette.INK_SOFT)
              .onClick(() => {
                this.isShown = false;
              })
          }
          .width('100%')

          Text(this.title)
            .fontFamily(Fonts.DISPLAY)
            .fontSize(34)
            .lineHeight(38)
            .fontColor(Palette.INK)
            .width('100%')
            .margin({ top: 8 })

          Text('Na podstawie Wikipedii · CC BY-SA 4.0')
            .fontFamily(Fonts.ITALIC)
            .fontSize(13)
            .fontColor(Palette.INK_FAINT)
            .width('100%')
            .margin({ top: 6, bottom: 16 })

          Scroll() {
            Text(this.content)
              .fontFamily(Fonts.TEXT)
              .fontSize(19)
              .lineHeight(30)
              .fontColor(Palette.INK)
              .width('100%')
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          .margin({ bottom: 24 })
        }
        .width('100%')
        .height('62%')
        .padding({ left: 24, right: 24 })
        .backgroundColor(Palette.PAPER)
        .borderRadius({ topLeft: 24, topRight: 24 })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .onClick(() => {
          // taps inside the sheet do not close it
        })
        .transition(TransitionEffect.move(TransitionEdge.BOTTOM)
          .animation({ duration: 420, curve: Motion.EASE_OUT }))
      }
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .hitTestBehavior(this.isShown ? HitTestMode.Default : HitTestMode.Transparent)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
