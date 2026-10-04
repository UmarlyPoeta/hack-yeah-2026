// Home screen card: photo of the nearest landmark, its name and distance, and "Posłuchaj" that opens it.
// Square corners like the app; the system clips the card's outer corners itself.
let storage = new LocalStorage();

@Entry(storage)
@Component
struct PlaceCard {
  @LocalStorageProp('placeId') placeId: string = '';
  @LocalStorageProp('name') name: string = '';
  @LocalStorageProp('distance') distance: string = '';
  @LocalStorageProp('imageKey') imageKey: string = '';
  @LocalStorageProp('hasPlace') hasPlace: boolean = false;

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.imageKey.length > 0) {
        Image(`memory://${this.imageKey}`)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      }
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [[$r('app.color.photo_chip_bg'), 0], ['#00000000', 0.35], [$r('app.color.hero_gradient_end'), 1]]
        })

      Text($r('app.string.brand_name'))
        .fontSize(14)
        .fontWeight(FontWeight.Bolder)
        .fontColor($r('app.color.on_primary'))
        .position({ x: 12, y: 10 })

      Column({ space: 2 }) {
        Text(this.hasPlace ? this.name : $r('app.string.discover_empty_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.distance.length > 0) {
          Text(this.distance)
            .fontSize(12)
            .fontColor($r('app.color.on_primary'))
            .opacity(0.85)
        }
        if (this.hasPlace) {
          Row({ space: 6 }) {
            Text($r('app.string.widget_listen'))
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text'))
            Image($r('app.media.ic_arrow_right_dark')).width(14).height(14)
          }
          .height(32)
          .padding({ left: 10, right: 10 })
          .borderRadius(2)
          .backgroundColor($r('app.color.surface'))
          .margin({ top: 8 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding(12)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.ink'))
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { placeId: this.placeId }
      });
    })
  }
}
