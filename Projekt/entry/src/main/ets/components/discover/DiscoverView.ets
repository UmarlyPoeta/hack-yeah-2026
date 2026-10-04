// "Odkrywaj" tab: the first landmark of the queue as a large photo, the rest of the queue below.
import { Fonts } from '../../common/Fonts';
import { distanceM } from '../../guide/geo';
import { distanceLabel, Place, placeImage, shortName } from '../../model/Place';
import { City } from '../../store/CityInfo';
import { setStatusBarLight } from '../../common/StatusBar';
import { Logo, PrimaryButton } from '../common/Controls';
import { BookmarkButton } from '../common/BookmarkButton';

@Component
export struct DiscoverView {
  onOpen: (place: Place) => void = () => {};
  @StorageLink('queue') queue: Place[] = [];
  @StorageProp('city') city: City | null = null;
  @State cityExpanded: boolean = false;
  @StorageProp('queueLoading') loading: boolean = false;
  @StorageProp('userLat') userLat: number = 0;
  @StorageProp('userLon') userLon: number = 0;
  @StorageProp('topInset') topInset: number = 0;
  private scroller: Scroller = new Scroller();
  private overPhoto: boolean = true;

  build() {
    if (this.queue.length === 0) {
      this.Empty()
    } else {
      Scroll(this.scroller) {
        Column() {
          this.Hero(this.queue[0])
          if (this.queue.length > 1) {
            this.Queue()
          }
          if (this.city !== null) {
            this.CityCard(this.city)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .align(Alignment.Top)
      .backgroundColor($r('app.color.surface'))
      .onDidScroll(() => this.updateStatusBar())
    }
  }

  // white status bar icons over the photo, dark ones once white content is under them
  private updateStatusBar(): void {
    const ui = this.getUIContext();
    // hero_height (420 vp) minus the status bar: below that, white content is under the icons
    const overPhoto = this.scroller.currentOffset().yOffset < 420 - this.topInset - 24;
    if (overPhoto !== this.overPhoto) {
      this.overPhoto = overPhoto;
      setStatusBarLight(ui.getHostContext(), overPhoto);
    }
  }

  @Builder
  Hero(place: Place) {
    Stack({ alignContent: Alignment.BottomStart }) {
      Image(placeImage(place))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .backgroundColor($r('app.color.placeholder'))
        .accessibilityText(place.name)
        .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
      // keeps white text readable on any photo: dark at the top (status bar) and at the bottom (title)
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [[$r('app.color.photo_chip_bg'), 0], ['#00000000', 0.28], ['#00000000', 0.45],
            [$r('app.color.hero_gradient_end'), 1]]
        })

      Column({ space: 6 }) {
        Text(this.distanceText(place))
          .fontSize($r('app.float.font_caption'))
          .fontFamily(Fonts.BOLD)
          .fontColor($r('app.color.on_primary'))
          .letterSpacing(1)
          .opacity(0.9)
        Text(shortName(place))
          .fontSize($r('app.float.font_hero_title'))
          .fontFamily(Fonts.EXTRABOLD)
          .fontColor($r('app.color.on_primary'))
          .letterSpacing(-0.6)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Column() {
          PrimaryButton($r('app.string.listen'), false, () => this.onOpen(place))
        }
        .width('100%')
        .margin({ top: 14 })
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, bottom: 20 })

      Row() {
        Logo($r('app.float.font_title'), $r('app.color.on_primary'))
        Blank()
        BookmarkButton({ place: place })
      }
      .width('100%')
      .padding({ left: 20, right: 16 })
      .position({ x: 0, y: this.topInset + 8 })
    }
    .width('100%')
    .height($r('app.float.hero_height'))
    .onClick(() => this.onOpen(place))
  }

  @Builder
  Queue() {
    Row() {
      Text($r('app.string.discover_queue'))
        .fontSize($r('app.float.font_title'))
        .fontFamily(Fonts.EXTRABOLD)
        .fontColor($r('app.color.text'))
      Blank()
      if (this.loading) {
        Row({ space: 6 }) {
          LoadingProgress().width(16).height(16).color($r('app.color.text_secondary'))
          Text($r('app.string.discover_updating'))
            .fontSize($r('app.float.font_caption'))
            .fontFamily(Fonts.SEMIBOLD)
            .fontColor($r('app.color.text_secondary'))
        }
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 24, bottom: 12 })

    List({ space: 12 }) {
      ForEach(this.queue.slice(1), (place: Place) => {
        ListItem() {
          this.Card(place)
        }
        .transition(TransitionEffect.OPACITY.animation({ duration: 250 }))
      }, (place: Place) => place.id)
    }
    .listDirection(Axis.Horizontal)
    .scrollBar(BarState.Off)
    .contentStartOffset(20)
    .contentEndOffset(20)
    .width('100%')
    .height(190)
  }

  @Builder
  Card(place: Place) {
    Column({ space: 8 }) {
      Image(placeImage(place))
        .width('100%')
        .height($r('app.float.queue_card_image_height'))
        .objectFit(ImageFit.Cover)
        .borderRadius($r('app.float.radius'))
        .backgroundColor($r('app.color.placeholder'))
        .accessibilityText(place.name)
      Column({ space: 2 }) {
        Text(shortName(place))
          .fontSize($r('app.float.font_label'))
          .fontFamily(Fonts.BOLD)
          .fontColor($r('app.color.text'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.distance(place))
          .fontSize($r('app.float.font_caption'))
          .fontFamily(Fonts.MEDIUM)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .width($r('app.float.queue_card_width'))
    .onClick(() => this.onOpen(place))
  }

  // "Jesteś w": the town from Wikipedia, photo on top, intro that unfolds on tap
  @Builder
  CityCard(city: City) {
    Column() {
      if (city.imageUrl.length > 0) {
        Image(city.imageUrl)
          .width('100%')
          .height(180)
          .objectFit(ImageFit.Cover)
          .borderRadius($r('app.float.radius'))
          .backgroundColor($r('app.color.placeholder'))
          .accessibilityText(city.name)
      }
      Text($r('app.string.city_label'))
        .fontSize($r('app.float.font_caption'))
        .fontFamily(Fonts.BOLD)
        .fontColor($r('app.color.accent'))
        .letterSpacing(1.5)
        .textCase(TextCase.UpperCase)
        .margin({ top: 16 })
      Text(city.name)
        .fontSize($r('app.float.font_hero_title'))
        .fontFamily(Fonts.EXTRABOLD)
        .fontColor($r('app.color.text'))
        .letterSpacing(-0.6)
        .margin({ top: 4 })
      if (city.description.length > 0) {
        Text(city.description)
          .fontSize($r('app.float.font_small'))
          .fontFamily(Fonts.MEDIUM)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 2 })
      }
      Text(city.extract)
        .fontSize($r('app.float.font_body'))
        .fontFamily(Fonts.REGULAR)
        .lineHeight(23)
        .fontColor($r('app.color.text'))
        .maxLines(this.cityExpanded ? 40 : 4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 12 })
        .animation({ duration: 250, curve: Curve.EaseOut })
      Row() {
        Text(this.cityExpanded ? $r('app.string.read_less') : $r('app.string.read_more'))
          .fontSize($r('app.float.font_label'))
          .fontFamily(Fonts.BOLD)
          .fontColor($r('app.color.accent'))
        Blank()
        Text($r('app.string.source_wikipedia'))
          .fontSize($r('app.float.font_caption'))
          .fontFamily(Fonts.REGULAR)
          .fontColor($r('app.color.text_muted'))
      }
      .width('100%')
      .constraintSize({ minHeight: $r('app.float.touch_min') })
      .onClick(() => {
        this.cityExpanded = !this.cityExpanded;
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 20, right: 20, top: 28, bottom: 24 })
    .border({ width: { top: 1 }, color: { top: $r('app.color.separator') } })
    .margin({ top: 12 })
  }

  @Builder
  Empty() {
    Column({ space: 10 }) {
      Logo($r('app.float.font_logo'), $r('app.color.text'))
      LoadingProgress().width(28).height(28).color($r('app.color.accent')).margin({ top: 16 })
      Text($r('app.string.discover_empty_title'))
        .fontSize($r('app.float.font_title'))
        .fontFamily(Fonts.EXTRABOLD)
        .fontColor($r('app.color.text'))
      Text($r('app.string.discover_empty_body'))
        .fontSize($r('app.float.font_label'))
        .fontFamily(Fonts.REGULAR)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.surface'))
  }

  private distance(place: Place): string {
    if (this.userLat === 0 && this.userLon === 0) {
      return '';
    }
    return distanceLabel(distanceM({ lat: this.userLat, lon: this.userLon }, place));
  }

  /** "W POBLIŻU · 350 M OD CIEBIE" */
  private distanceText(place: Place): string {
    const ctx = this.getUIContext().getHostContext();
    if (ctx === undefined) {
      return '';
    }
    const nearby = ctx.resourceManager.getStringSync($r('app.string.discover_nearby').id);
    const d = this.distance(place);
    const text = d.length > 0 ? `${nearby} · ${ctx.resourceManager.getStringSync($r('app.string.from_you').id, d)}` : nearby;
    return text.toUpperCase();
  }
}
