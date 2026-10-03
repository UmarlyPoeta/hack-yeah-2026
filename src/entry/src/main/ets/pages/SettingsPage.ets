import router from '@ohos.router';

@Entry
@Component
struct SettingsPage {
  @State selectedInterest: string = 'historia';

  build() {
    Column() {
      // Górny pasek powrotu
      Row() {
        Button('← Wróć')
          .backgroundColor(Color.Transparent)
          .fontColor('#007DFF')
          .onClick(() => {
            router.back();
          })
        Blank()
      }
      .width('100%')
      .padding(16)
      .backgroundColor(Color.White)

      // Panel ustawień
      Column() {
        Text('Ustawienia spaceru')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111111')
          .margin({ bottom: 20 })
          .alignSelf(ItemAlign.Start)

        // Karta zainteresowań
        Column() {
          Text('Wybierz główne zainteresowania')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .margin({ bottom: 12 })
            .alignSelf(ItemAlign.Start)

          Row() {
            Button('Historia')
              .backgroundColor(this.selectedInterest === 'historia' ? '#007DFF' : '#E0E0E0')
              .fontColor(this.selectedInterest === 'historia' ? Color.White : Color.Black)
              .height(36)
              .onClick(() => { this.selectedInterest = 'historia'; })

            Button('Architektura')
              .backgroundColor(this.selectedInterest === 'architektura' ? '#007DFF' : '#E0E0E0')
              .fontColor(this.selectedInterest === 'architektura' ? Color.White : Color.Black)
              .height(36)
              .margin({ left: 10 })
              .onClick(() => { this.selectedInterest = 'architektura'; })
          }
          .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor(Color.White)
        .borderRadius(12)
        .shadow({ radius: 4, color: '#05000000', offsetX: 0, offsetY: 2 })
      }
      .width('90%')
      .margin({ top: 20 })

      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}