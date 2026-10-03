@Component
export struct Teleprompter {
  @Prop currentText: string = 'Oczekiwanie na narrację...';
  @Prop poiName: string = 'Najbliższy punkt';
  @Prop segmentKind: string = 'WELCOME';
  onPlayClick: () => void = () => {};

  build() {
    Column() {
      Row() {
        Text(this.segmentKind)
          .fontSize(12)
          .fontColor(Color.White)
          .backgroundColor('#007DFF')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(4)
        Blank()
        Text(this.poiName)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
      }
      .width('100%')
      .margin({ bottom: 12 })

      Text(this.currentText)
        .fontSize(18)
        .fontColor('#111111')
        .lineHeight(26)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ bottom: 16 })

      Button('Odsłuchaj narrację (Test MP3)')
        .onClick(() => this.onPlayClick())
        .width('100%')
        .height(40)
    }
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(12)
    .shadow({ radius: 8, color: '#10000000', offsetX: 0, offsetY: 4 })
    .width('90%')
  }
}