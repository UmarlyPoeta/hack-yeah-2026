import router from '@ohos.router';
import common from '@ohos.app.ability.common';
import { Eyebrow, Fonts, Palette, registerFonts } from '../common/Theme';
import { RouteMap } from '../components/RouteMap';

@Entry
@Component
struct StartPage {
  aboutToAppear(): void {
    registerFonts(this.getUIContext());
  }

  build() {
    Column() {
      Row() {
        Eyebrow('KRAKÓW · STARE MIASTO', Palette.BRICK)
        Blank()
        Text('Zamknij')
          .fontSize(13)
          .fontColor(Palette.INK_FAINT)
          .onClick(() => {
            const context = getContext(this) as common.UIAbilityContext;
            context.terminateSelf();
          })
      }
      .width('100%')
      .margin({ top: 12 })

      Text('Spacer\nz historią')
        .fontFamily(Fonts.DISPLAY)
        .fontSize(54)
        .lineHeight(54)
        .fontColor(Palette.INK)
        .width('100%')
        .margin({ top: 28 })

      Text('Przewodnik, który idzie razem z tobą i opowiada o tym, co właśnie mijasz.')
        .fontFamily(Fonts.ITALIC)
        .fontSize(19)
        .lineHeight(26)
        .fontColor(Palette.INK_SOFT)
        .width('100%')
        .margin({ top: 14 })

      RouteMap()
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 20, bottom: 12 })

      Row() {
        Text('Barbakan — Wawel')
          .fontFamily(Fonts.TEXT_MEDIUM)
          .fontSize(16)
          .fontColor(Palette.INK)
        Blank()
        Text('1,5 km · ok. 20 min')
          .fontSize(13)
          .fontColor(Palette.INK_SOFT)
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
      .border({ width: { top: 1, bottom: 1 }, color: Palette.RULE })

      Button({ type: ButtonType.Normal }) {
        Row() {
          Text('Rozpocznij spacer')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(Palette.PAPER)
          Blank()
          Text('→')
            .fontSize(20)
            .fontColor(Palette.PAPER)
        }
        .width('100%')
        .padding({ left: 22, right: 22 })
      }
      .width('100%')
      .height(58)
      .borderRadius(14)
      .backgroundColor(Palette.INK)
      .margin({ top: 20 })
      .onClick(() => {
        router.pushUrl({ url: 'pages/WalkPage' });
      })

      Row() {
        Text('Lokalizacja tylko na czas spaceru, bez stałych uprawnień.')
          .fontSize(12)
          .fontColor(Palette.INK_SOFT)
          .layoutWeight(1)
        Text('Jak to działa')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(Palette.BRICK)
          .margin({ left: 12 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/PrivacyPage' });
          })
      }
      .width('100%')
      .margin({ top: 14 })

      Text('Zainteresowania')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(Palette.INK)
        .decoration({ type: TextDecorationType.Underline, color: Palette.RULE })
        .margin({ top: 10, bottom: 8 })
        .alignSelf(ItemAlign.Start)
        .onClick(() => {
          router.pushUrl({ url: 'pages/SettingsPage' });
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, bottom: 16 })
    .backgroundColor(Palette.PAPER)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
