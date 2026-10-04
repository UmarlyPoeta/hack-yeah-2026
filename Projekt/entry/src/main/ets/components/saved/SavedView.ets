// "Zapisane" tab: landmarks saved for later (SavedPlaces), newest first.
import { Fonts } from '../../common/Fonts';
import { Place, placeImage, shortName } from '../../model/Place';
import { SavedPlaces } from '../../store/SavedPlaces';

@Component
export struct SavedView {
  onOpen: (place: Place) => void = () => {};
  @StorageLink('saved') saved: Place[] = [];
  @StorageProp('topInset') topInset: number = 0;

  build() {
    Column() {
      Text($r('app.string.saved_title'))
        .fontSize($r('app.float.font_hero_title'))
        .fontFamily(Fonts.EXTRABOLD)
        .fontColor($r('app.color.text'))
        .letterSpacing(-0.6)
      Text($r('app.string.saved_hint'))
        .fontSize($r('app.float.font_small'))
        .fontFamily(Fonts.REGULAR)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 4 })

      if (this.saved.length === 0) {
        this.Empty()
      } else {
        List() {
          ForEach(this.saved, (place: Place) => {
            ListItem() {
              this.Row(place)
            }
            .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
          }, (place: Place) => place.id)
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 16 })
        .scrollBar(BarState.Off)
        .divider({ strokeWidth: 1, color: $r('app.color.separator') })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 20, right: 20, top: this.topInset + 16 })
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  Row(place: Place) {
    Row({ space: 14 }) {
      Image(placeImage(place))
        .width($r('app.float.thumb_size'))
        .height($r('app.float.thumb_size'))
        .borderRadius($r('app.float.radius'))
        .objectFit(ImageFit.Cover)
        .backgroundColor($r('app.color.placeholder'))
        .accessibilityText(place.name)
      Column({ space: 3 }) {
        Text(shortName(place))
          .fontSize($r('app.float.font_place'))
          .fontFamily(Fonts.BOLD)
          .fontColor($r('app.color.text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(place.summary)
          .fontSize($r('app.float.font_small'))
          .fontFamily(Fonts.REGULAR)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.ic_close')).width(18).height(18)
      }
      .width($r('app.float.touch_min'))
      .height($r('app.float.touch_min'))
      .borderRadius($r('app.float.radius'))
      .backgroundColor(Color.Transparent)
      .accessibilityText($r('app.string.a11y_remove'))
      .onClick(() => SavedPlaces.remove(place.id))
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => this.onOpen(place))
  }

  @Builder
  Empty() {
    Column({ space: 10 }) {
      Image($r('app.media.ic_saved_empty')).width(28).height(28)
      Text($r('app.string.saved_empty_title'))
        .fontSize($r('app.float.font_title'))
        .fontFamily(Fonts.EXTRABOLD)
        .fontColor($r('app.color.text'))
        .margin({ top: 6 })
      Text($r('app.string.saved_empty_body'))
        .fontSize($r('app.float.font_label'))
        .fontFamily(Fonts.REGULAR)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }
}
