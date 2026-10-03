import router from '@ohos.router';
import { Eyebrow, Fonts, Palette } from '../common/Theme';

class InterestOption {
  id: string;     // Interest in docs/CONTRACTS.md
  label: string;

  constructor(id: string, label: string) {
    this.id = id;
    this.label = label;
  }
}

const OPTIONS: InterestOption[] = [
  new InterestOption('historia', 'Historia'),
  new InterestOption('architektura', 'Architektura'),
  new InterestOption('sztuka', 'Sztuka'),
  new InterestOption('ludzie', 'Ludzie'),
  new InterestOption('legendy', 'Legendy'),
];

@Entry
@Component
struct SettingsPage {
  @State selected: string[] = ['historia'];
  @State voiceOn: boolean = true;

  build() {
    Column() {
      Text('← Wróć')
        .fontSize(15)
        .fontColor(Palette.INK_SOFT)
        .padding({ top: 12, bottom: 12, right: 12 })
        .onClick(() => {
          router.back();
        })

      Eyebrow('USTAWIENIA', Palette.BRICK)
      Text('O czym mam opowiadać?')
        .fontFamily(Fonts.DISPLAY)
        .fontSize(36)
        .lineHeight(40)
        .fontColor(Palette.INK)
        .margin({ top: 8 })
      Text('Wybierz jedno lub kilka. Przewodnik dobierze wątki do miejsc na trasie.')
        .fontFamily(Fonts.ITALIC)
        .fontSize(17)
        .lineHeight(24)
        .fontColor(Palette.INK_SOFT)
        .margin({ top: 8, bottom: 22 })

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(OPTIONS, (o: InterestOption) => {
          Text(o.label)
            .fontSize(16)
            .fontColor(this.isOn(o.id) ? Palette.PAPER : Palette.INK)
            .backgroundColor(this.isOn(o.id) ? Palette.INK : Color.Transparent)
            .border({ width: 1, color: Palette.INK, radius: 20 })
            .padding({ left: 18, right: 18, top: 10, bottom: 10 })
            .margin({ right: 10, bottom: 10 })
            .onClick(() => this.toggle(o.id))
        }, (o: InterestOption) => o.id)
      }
      .width('100%')

      Row() {
        Column() {
          Text('Głos przewodnika')
            .fontFamily(Fonts.TEXT_MEDIUM)
            .fontSize(18)
            .fontColor(Palette.INK)
          Text(this.voiceOn ? 'Narracja czytana na głos' : 'Tylko tekst na ekranie')
            .fontSize(13)
            .fontColor(Palette.INK_FAINT)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.voiceOn })
          .selectedColor(Palette.INK)
          .onChange((on: boolean) => {
            this.voiceOn = on;
          })
      }
      .width('100%')
      .padding({ top: 18, bottom: 18 })
      .margin({ top: 18 })
      .border({ width: { top: 1, bottom: 1 }, color: Palette.RULE })

      Blank()
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 24, right: 24 })
    .backgroundColor(Palette.PAPER)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private isOn(id: string): boolean {
    return this.selected.indexOf(id) >= 0;
  }

  private toggle(id: string): void {
    if (this.isOn(id)) {
      if (this.selected.length > 1) {
        this.selected = this.selected.filter((x: string) => x !== id);
      }
    } else {
      this.selected = this.selected.concat([id]);
    }
  }
}
