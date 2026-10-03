@Entry
@Component
struct Index {
  @State message: string = 'Hello World';

  build() {
    RelativeContainer() {
      Text(this.message)
        .id('HelloWorld')
        .fontSize($r('app.float.page_text_font_size'))
        .fontWeight(FontWeight.Bold)
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
        .onClick(() => {
          this.message = 'Welcome';
        })
      // temporary entry to the guide engine debug replay (P2), until P5's start page lands
      Button('Debug przewodnika')
        .id('GuideDebug')
        .alignRules({
          bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
        .margin({ bottom: 48 })
        .onClick(() => {
          this.getUIContext().getRouter().pushUrl({ url: 'pages/GuideDebugPage' });
        })
    }
    .height('100%')
    .width('100%')
  }
}