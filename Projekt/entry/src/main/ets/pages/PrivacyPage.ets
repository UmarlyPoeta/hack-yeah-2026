import router from '@ohos.router';

@Entry
@Component
struct PrivacyPage {
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

      // Treść zasady prywatności
      Scroll() {
        Column() {
          Text('Polityka Prywatności i Lokalizacja')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#111111')
            .margin({ bottom: 16 })

          Text('1. Aplikacja "Spacer z historią" szanuje Twoją prywatność.\n\n' +
            '2. Lokalizacja GPS jest pobierana wyłącznie w trakcie aktywnego spaceru po kliknięciu przycisku autoryzacji.\n\n' +
            '3. Żadne dane o Twojej pozycji nie są zapisywane w tle ani przekazywane do zewnętrznych podmiotów — do serwera trafiają wyłącznie anonimowe identyfikatory punktów (POI) w celu pobrania treści narracji.')
            .fontSize(15)
            .fontColor('#333333')
            .lineHeight(24)
        }
        .width('100%')
        .padding(20)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}