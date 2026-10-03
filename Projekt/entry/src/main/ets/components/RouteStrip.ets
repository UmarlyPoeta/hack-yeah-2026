import { Eyebrow, Fonts, Palette } from '../common/Theme';

@Component
export struct RouteStrip {
  @Prop nextPoiName: string = 'Brama Floriańska';
  @Prop distanceM: number = 120;
  @Prop etaSeconds: number = 90;

  build() {
    Column() {
      Eyebrow('NASTĘPNY PRZYSTANEK')
      Text(this.nextPoiName)
        .fontFamily(Fonts.DISPLAY)
        .fontSize(32)
        .lineHeight(36)
        .fontColor(Palette.INK)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
      Row({ space: 10 }) {
        Text(`${Math.round(this.distanceM)} m`)
          .fontFamily(Fonts.TEXT_MEDIUM)
          .fontSize(20)
          .fontColor(Palette.BRICK)
        Text(this.etaText())
          .fontSize(14)
          .fontColor(Palette.INK_SOFT)
      }
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: 8 })
    }
    .alignItems(HorizontalAlign.Start)
  }

  private etaText(): string {
    const min = Math.max(1, Math.round(this.etaSeconds / 60));
    return `ok. ${min} min pieszo`;
  }
}
