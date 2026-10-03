import router from '@ohos.router';
import common from '@ohos.app.ability.common';

@Entry
@Component
struct StartPage {
  build() {
    Column() {
      Text('Spacer z historią')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#111111')
        .margin({ bottom: 8 })

      Text('Twój osobisty przewodnik, który idzie razem z Tobą.')
        .fontSize(14)
        .fontColor('#666666')
        .textAlign(TextAlign.Center)
        .width('85%')
        .margin({ bottom: 40 })

      Button('Rozpocznij spacer')
        .width('85%')
        .height(50)
        .backgroundColor('#007DFF')
        .fontColor(Color.White)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .borderRadius(25)
        .margin({ bottom: 16 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/WalkPage' });
        })

      Button('Wyjdź z aplikacji')
        .width('85%')
        .height(50)
        .backgroundColor('#FF4D4F')
        .fontColor(Color.White)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .borderRadius(25)
        .onClick(() => {
          let context = getContext(this) as common.UIAbilityContext;
          context.terminateSelf();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(20)
  }
}