import router from '@ohos.router';
import { Eyebrow, Fonts, Palette } from '../common/Theme';

class Point {
  no: string;
  title: string;
  body: string;

  constructor(no: string, title: string, body: string) {
    this.no = no;
    this.title = title;
    this.body = body;
  }
}

const POINTS: Point[] = [
  new Point('1', 'Tylko gdy idziesz',
    'Pozycję dostajemy wyłącznie po dotknięciu przycisku lokalizacji. Aplikacja nie ma stałego uprawnienia.'),
  new Point('2', 'Znika, gdy odchodzisz',
    'Po wygaszeniu ekranu albo wyjściu z aplikacji dostęp wygasa, a spacer się wstrzymuje.'),
  new Point('3', 'Na serwer trafiają tylko miejsca',
    'Do narracji wysyłamy identyfikatory zabytków, nie twoją trasę. Serwer nie zapisuje pozycji.'),
];

@Entry
@Component
struct PrivacyPage {
  build() {
    Column() {
      Text('← Wróć')
        .fontSize(15)
        .fontColor(Palette.INK_SOFT)
        .padding({ top: 12, bottom: 12, right: 12 })
        .onClick(() => {
          router.back();
        })

      Eyebrow('PRYWATNOŚĆ', Palette.BRICK)
      Text('Twoja lokalizacja zostaje przy tobie')
        .fontFamily(Fonts.DISPLAY)
        .fontSize(36)
        .lineHeight(40)
        .fontColor(Palette.INK)
        .margin({ top: 8, bottom: 20 })

      Scroll() {
        Column() {
          ForEach(POINTS, (p: Point) => {
            Row({ space: 16 }) {
              Text(p.no)
                .fontFamily(Fonts.DISPLAY)
                .fontSize(40)
                .lineHeight(40)
                .fontColor(Palette.BRICK)
                .width(28)
              Column() {
                Text(p.title)
                  .fontFamily(Fonts.TEXT_MEDIUM)
                  .fontSize(19)
                  .fontColor(Palette.INK)
                Text(p.body)
                  .fontFamily(Fonts.TEXT)
                  .fontSize(17)
                  .lineHeight(25)
                  .fontColor(Palette.INK_SOFT)
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .alignItems(VerticalAlign.Top)
            .padding({ top: 18, bottom: 18 })
            .border({ width: { top: 1 }, color: Palette.RULE })
          }, (p: Point) => p.no)
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 24, right: 24 })
    .backgroundColor(Palette.PAPER)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
