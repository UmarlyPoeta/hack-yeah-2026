@Component
export struct DeepDiveSheet {
  @Link isShown: boolean;
  @Prop title: string;
  @Prop content: string;

  build() {
    if (this.isShown) {
      Stack({ alignContent: Alignment.Bottom }) {
        // Półprzezroczyste tło – kliknięcie zamyka arkusz
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#60000000')
          .onClick(() => {
            this.isShown = false;
          })

        // Właściwy panel dolny
        Column() {
          // Uchwyt arkusza
          Row()
            .width(40)
            .height(4)
            .backgroundColor('#CCCCCC')
            .borderRadius(2)
            .margin({ top: 8, bottom: 16 })

          // Nagłówek i przycisk zamknięcia
          Row() {
            Text(this.title)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#111111')
            Blank()
            Button('✕')
              .backgroundColor(Color.Transparent)
              .fontColor('#666666')
              .fontSize(16)
              .onClick(() => {
                this.isShown = false;
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .margin({ bottom: 12 })

          // Treść przewijana
          Scroll() {
            Text(this.content)
              .fontSize(15)
              .fontColor('#333333')
              .lineHeight(22)
              .width('100%')
              .padding({ left: 16, right: 16 })
          }
          .layoutWeight(1)
          .margin({ bottom: 20 })
        }
        .width('100%')
        .height('50%')
        .backgroundColor(Color.White)
        .borderRadius({ topLeft: 20, topRight: 20 })
        .onClick(() => {
          // Zapobiega zamknięciu arkusza po kliknięciu wewnątrz jego białego obszaru
        })
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
    }
  }
}