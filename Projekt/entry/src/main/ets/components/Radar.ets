@Component
export struct Radar {
  @Prop poiName: string = 'Najbliższy obiekt';
  @Prop distanceM: number = 120;
  @Prop bearingAngle: number = 45;

  build() {
    Row() {
      Text('🧭')
        .fontSize(22)
        .margin({ right: 12 })

      Column() {
        Text('RADAR PRZESTRZENNY')
          .fontSize(10)
          .fontColor('#888888')
          .fontWeight(FontWeight.Bold)
        Text(`\({this.poiName} (\){this.distanceM} m)`)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Text(`Kąt: ${this.bearingAngle}°`)
        .fontSize(11)
        .fontColor('#007DFF')
        .fontWeight(FontWeight.Bold)
    }
    .width('90%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(10)
    .shadow({ radius: 4, color: '#05000000', offsetX: 0, offsetY: 2 })
  }
}