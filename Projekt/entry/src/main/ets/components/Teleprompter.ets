import { Eyebrow, Fonts, Palette } from '../common/Theme';

@Component
export struct Teleprompter {
  @Prop currentText: string = 'Oczekiwanie na narrację...';
  @Prop poiName: string = 'Najbliższy punkt';
  @Prop segmentKind: string = 'WELCOME';
  onPlayClick: () => void = () => {};

  build() {
    Column() {
      Row() {
        Eyebrow(this.kindLabel(), Palette.BRICK)
        Blank()
        Text(this.poiName)
          .fontFamily(Fonts.ITALIC)
          .fontSize(15)
          .fontColor(Palette.INK_SOFT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.End)
          .margin({ left: 12 })
      }
      .width('100%')

      Text(this.currentText)
        .fontFamily(Fonts.TEXT)
        .fontSize(22)
        .lineHeight(32)
        .fontColor(Palette.INK)
        .maxLines(5)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 14 })

      Row({ space: 14 }) {
        Stack() {
          Circle({ width: 52, height: 52 })
            .fill(Palette.INK)
          Polygon({ width: 16, height: 18 })
            .points([[0, 0], [16, 9], [0, 18]])
            .fill(Palette.PAPER)
            .margin({ left: 4 })
        }
        Column() {
          Text('Odsłuchaj narrację')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.INK)
          Text('głos przewodnika')
            .fontSize(12)
            .fontColor(Palette.INK_FAINT)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .margin({ top: 20 })
      .onClick(() => this.onPlayClick())
    }
    .width('100%')
    .padding(22)
    .backgroundColor(Palette.CARD)
    .borderRadius(18)
    .border({ width: 1, color: Palette.RULE, radius: 18 })
  }

  private kindLabel(): string {
    switch (this.segmentKind) {
      case 'WELCOME': return 'POWITANIE';
      case 'APPROACH': return 'ZBLIŻAMY SIĘ';
      case 'ARRIVAL': return 'NA MIEJSCU';
      case 'BRIDGE': return 'PO DRODZE';
      case 'DEEP_DIVE': return 'OPOWIEŚĆ';
      case 'MISSED': return 'MINĘLIŚMY';
      default: return this.segmentKind;
    }
  }
}
