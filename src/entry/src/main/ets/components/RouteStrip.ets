@Component
export struct RouteStrip {
  @Prop nextPoiName: string = 'Brama Floriańska';
  @Prop distanceM: number = 120;
  @Prop etaSeconds: number = 90;

  build() {
    Row() {
      Column() {
        Text('NASTĘPNY PUNKT')
          .fontSize(10)
          .fontColor('#888888')
          .fontWeight(FontWeight.Bold)
        Text(this.nextPoiName)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Column() {
        Text(`${this.distanceM} m`)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#007DFF')
        Text(`~${Math.round(this.etaSeconds / 60)} min`)
          .fontSize(11)
          .fontColor('#666666')
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('90%')
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(10)
    .shadow({ radius: 4, color: '#05000000', offsetX: 0, offsetY: 2 })
  }
}