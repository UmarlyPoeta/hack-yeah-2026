// "Zapisane" tab: preview of saved routes on mock data. Nothing is actually saved yet;
// the switch at the bottom shows the empty state.
import { Fonts } from '../../common/Fonts';
import { placesLabel } from '../../common/Labels';
import { Route } from '../../model/Route';

@Component
export struct SavedView {
  routes: Route[] = [];
  @State showEmpty: boolean = false;
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

      if (this.showEmpty || this.routes.length === 0) {
        this.Empty()
      } else {
        List({ space: 12 }) {
          ForEach(this.routes, (route: Route) => {
            ListItem() {
              this.RouteRow(route)
            }
          }, (route: Route) => route.id)
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 20 })
        .scrollBar(BarState.Off)
      }

      Text(this.showEmpty ? $r('app.string.saved_show_list') : $r('app.string.saved_show_empty'))
        .fontSize($r('app.float.font_label'))
        .fontFamily(Fonts.BOLD)
        .fontColor($r('app.color.accent'))
        .constraintSize({ minHeight: $r('app.float.touch_min') })
        .alignSelf(ItemAlign.Center)
        .onClick(() => {
          this.showEmpty = !this.showEmpty;
        })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 20, right: 20, top: this.topInset + 16 })
    .backgroundColor($r('app.color.surface'))
  }

  @Builder
  RouteRow(route: Route) {
    Row({ space: 14 }) {
      Image(route.cover)
        .width(72)
        .height(72)
        .borderRadius($r('app.float.stop_card_radius'))
        .objectFit(ImageFit.Cover)
        .accessibilityText(route.coverLabel)
      Column({ space: 3 }) {
        Text(route.title)
          .fontSize($r('app.float.font_place'))
          .fontFamily(Fonts.BOLD)
          .fontColor($r('app.color.text'))
        Text(route.subtitle)
          .fontSize($r('app.float.font_small'))
          .fontFamily(Fonts.REGULAR)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 12 }) {
          this.Meta($r('app.media.ic_route'), route.distanceLabel())
          this.Meta($r('app.media.ic_clock'), $r('app.string.metric_time', route.durationMin))
          this.Meta($r('app.media.ic_pin'), placesLabel(this.getUIContext(), route.stops.length))
        }
        .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .borderRadius($r('app.float.card_radius'))
    .border({ width: 1, color: $r('app.color.separator'), radius: $r('app.float.card_radius') })
  }

  @Builder
  Meta(icon: Resource, label: ResourceStr) {
    Row({ space: 4 }) {
      Image(icon).width(14).height(14)
      Text(label)
        .fontSize($r('app.float.font_caption'))
        .fontFamily(Fonts.SEMIBOLD)
        .fontColor($r('app.color.text'))
    }
  }

  @Builder
  Empty() {
    Column({ space: 10 }) {
      Column() {
        Image($r('app.media.ic_saved_empty')).width(28).height(28)
      }
      .width(64)
      .height(64)
      .borderRadius(32)
      .backgroundColor($r('app.color.accent_bg'))
      .justifyContent(FlexAlign.Center)
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
