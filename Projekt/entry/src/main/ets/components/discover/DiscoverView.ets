// "Odkrywaj" tab: route details, after docs/design/start.html.
import { Fonts } from '../../common/Fonts';
import { Route, RouteStop } from '../../model/Route';

@Component
export struct DiscoverView {
  route: Route | null = null;
  onStart: () => void = () => {};
  onShowMap: () => void = () => {};
  onEnableLocation: () => void = () => {};
  // true once location is authorized for this session (set by the walk session, P1); hides the prompt
  @StorageLink('locationAuthorized') locationAuthorized: boolean = false;
  @StorageProp('topInset') topInset: number = 0;

  build() {
    if (this.route !== null) {
      Column() {
        this.Hero(this.route)
        this.Sheet(this.route)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.surface'))
    }
  }

  @Builder
  Hero(route: Route) {
    Stack({ alignContent: Alignment.BottomStart }) {
      Image(route.cover)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .accessibilityText(route.coverLabel)
      // darkens the lower half so the white title stays readable on any photo
      Column()
        .width('100%')
        .height(160)
        .linearGradient({ direction: GradientDirection.Bottom, colors: [['#00000000', 0], [$r('app.color.hero_gradient_end'), 1]] })

      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Image($r('app.media.ic_headphones')).width(13).height(13)
          Text($r('app.string.badge_narrated'))
            .fontSize($r('app.float.font_caption'))
            .fontFamily(Fonts.SEMIBOLD)
            .fontColor($r('app.color.on_primary'))
        }
        .height(26)
        .padding({ left: 10, right: 10 })
        .borderRadius(13)
        .backgroundColor($r('app.color.photo_badge_bg'))

        Text(route.title)
          .fontSize($r('app.float.font_hero_title'))
          .fontFamily(Fonts.EXTRABOLD)
          .fontColor($r('app.color.on_primary'))
          .letterSpacing(-0.6)
          .margin({ top: 4 })
        Text(route.subtitle)
          .fontSize($r('app.float.font_body'))
          .fontFamily(Fonts.MEDIUM)
          .fontColor($r('app.color.on_primary'))
          .opacity(0.92)
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 20, right: 20, bottom: 37 })

      Row() {
        this.RoundButton($r('app.media.ic_back'), $r('app.string.a11y_back'), () => {})
        Blank()
        Row({ space: 10 }) {
          // preview only: saving routes is not implemented yet
          this.RoundButton($r('app.media.ic_bookmark'), $r('app.string.a11y_save'), () => {})
          this.RoundButton($r('app.media.ic_share'), $r('app.string.a11y_share'), () => {})
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .position({ x: 0, y: this.topInset + 8 })
    }
    .width('100%')
    .height($r('app.float.hero_height'))
  }

  @Builder
  RoundButton(icon: Resource, label: Resource, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      Image(icon).width(20).height(20)
    }
    .width($r('app.float.round_button_size'))
    .height($r('app.float.round_button_size'))
    .backgroundColor($r('app.color.round_button_bg'))
    .accessibilityText(label)
    .onClick(action)
  }

  @Builder
  Sheet(route: Route) {
    Column() {
      Scroll() {
        Column() {
          Row() {
            this.Metric($r('app.media.ic_route'), route.distanceLabel())
            this.Metric($r('app.media.ic_clock'), $r('app.string.metric_time', route.durationMin))
            this.Metric($r('app.media.ic_pin'), $r('app.string.metric_places', route.stops.length))
          }
          .width('100%')
          .padding({ left: 20, right: 20 })

          if (!this.locationAuthorized) {
            Column() {
              this.LocationPrompt()
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 18 })
          }

          Row() {
            Text($r('app.string.on_the_way'))
              .fontSize($r('app.float.font_title'))
              .fontFamily(Fonts.EXTRABOLD)
              .fontColor($r('app.color.text'))
              .letterSpacing(-0.2)
            Blank()
            Text($r('app.string.route_map'))
              .fontSize($r('app.float.font_label'))
              .fontFamily(Fonts.BOLD)
              .fontColor($r('app.color.accent'))
              .constraintSize({ minHeight: $r('app.float.touch_min') })
              .onClick(() => this.onShowMap())
          }
          .width('100%')
          .padding({ left: 20, right: 20 })
          .margin({ top: 12 })

          Scroll() {
            Row({ space: 12 }) {
              ForEach(route.stops.slice(1), (stop: RouteStop) => {
                this.StopCard(stop, route.legLabel(stop.num - 1))
              }, (stop: RouteStop) => `${stop.num}`)
            }
            .padding({ left: 20, right: 20 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .margin({ top: 2 })

          Column() {
            Button({ type: ButtonType.Capsule }) {
              Row({ space: 10 }) {
                Image($r('app.media.ic_play')).width(20).height(20)
                Text($r('app.string.start_walk'))
                  .fontSize($r('app.float.font_button'))
                  .fontFamily(Fonts.BOLD)
                  .fontColor($r('app.color.on_primary'))
              }
            }
            .width('100%')
            .height($r('app.float.button_primary_height'))
            .backgroundColor($r('app.color.button_primary'))
            .onClick(() => this.onStart())
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 20, bottom: 20 })
        }
        .padding({ top: 20 })
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.surface'))
    .borderRadius({ topLeft: $r('app.float.sheet_radius'), topRight: $r('app.float.sheet_radius') })
    .translate({ y: -16 })
    .margin({ bottom: -16 })
  }

  @Builder
  Metric(icon: Resource, label: ResourceStr) {
    Row({ space: 8 }) {
      Image(icon).width(18).height(18)
      Text(label)
        .fontSize($r('app.float.font_label'))
        .fontFamily(Fonts.SEMIBOLD)
        .fontColor($r('app.color.text'))
    }
    .layoutWeight(1)
  }

  @Builder
  LocationPrompt() {
    Row({ space: 12 }) {
      Image($r('app.media.ic_navigate')).width(22).height(22)
      Text($r('app.string.location_hint'))
        .fontSize(13.5)
        .lineHeight(19)
        .fontFamily(Fonts.MEDIUM)
        .fontColor($r('app.color.accent_on_bg'))
        .layoutWeight(1)
      // UI only: the location authorization is wired by the walk session (P1). LocationButton (security
      // component) is not in the installed SDK (HarmonyOS 6.1.1 / API 24), see the PR description.
      Button($r('app.string.enable'))
        .height(36)
        .padding({ left: 14, right: 14 })
        .fontSize(13)
        .fontFamily(Fonts.BOLD)
        .fontColor($r('app.color.on_primary'))
        .backgroundColor($r('app.color.accent'))
        .constraintSize({ minHeight: $r('app.float.touch_min') })
        .onClick(() => this.onEnableLocation())
    }
    .width('100%')
    .padding({ left: 14, right: 12, top: 10, bottom: 10 })
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor($r('app.color.accent_bg'))
  }

  @Builder
  StopCard(stop: RouteStop, leg: string) {
    Column({ space: 8 }) {
      Stack() {
        Image(stop.image)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius($r('app.float.stop_card_radius'))
          .accessibilityText(stop.name)
        Text(`${stop.num}`)
          .width($r('app.float.badge_size'))
          .height($r('app.float.badge_size'))
          .borderRadius(12)
          .backgroundColor($r('app.color.surface'))
          .fontSize($r('app.float.font_caption'))
          .fontFamily(Fonts.EXTRABOLD)
          .fontColor($r('app.color.text'))
          .textAlign(TextAlign.Center)
          .position({ x: 8, y: 8 })
        if (leg.length > 0) {
          Text(leg)
            .height($r('app.float.badge_size'))
            .padding({ left: 8, right: 8 })
            .borderRadius(12)
            .backgroundColor($r('app.color.photo_chip_bg'))
            .fontSize($r('app.float.font_caption'))
            .fontFamily(Fonts.BOLD)
            .fontColor($r('app.color.on_primary'))
            .markAnchor({ x: '100%', y: '100%' })
            .position({ x: '100%', y: '100%' })
            .offset({ x: -8, y: -8 })
        }
      }
      .width('100%')
      .height($r('app.float.stop_card_image_height'))

      Column({ space: 2 }) {
        Text(stop.name)
          .fontSize($r('app.float.font_body'))
          .fontFamily(Fonts.BOLD)
          .fontColor($r('app.color.text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(stop.caption)
          .fontSize(12.5)
          .fontFamily(Fonts.REGULAR)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .width($r('app.float.stop_card_width'))
  }
}
