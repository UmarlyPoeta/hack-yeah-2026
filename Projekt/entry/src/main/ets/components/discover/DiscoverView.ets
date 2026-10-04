// "Odkrywaj" tab: the first landmark of the queue as a large photo, the rest of the queue below.
import { Fonts } from '../../common/Fonts';
import { distanceM } from '../../guide/geo';
import { distanceLabel, Place, placeImage, shortName } from '../../model/Place';
import { SavedPlaces } from '../../store/SavedPlaces';
import { Logo, PhotoIconButton, PrimaryButton } from '../common/Controls';

@Component
export struct DiscoverView {
  onOpen: (place: Place) => void = () => {};
  @StorageLink('queue') queue: Place[] = [];
  @StorageLink('saved') saved: Place[] = [];
  @StorageProp('queueLoading') loading: boolean = false;
  @StorageProp('userLat') userLat: number = 0;
  @StorageProp('userLon') userLon: number = 0;
  @StorageProp('topInset') topInset: number = 0;

  build() {
    if (this.queue.length === 0) {
      this.Empty()
    } else {
      Scroll() {
        Column() {
          this.Hero(this.queue[0])
          if (this.queue.length > 1) {
            this.Queue()
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
        PhotoIconButton(this.isSaved(place.id) ? $r('app.media.ic_bookmark_light_on') : $r('app.media.ic_bookmark_light'),
          this.isSaved(place.id) ? $r('app.string.a11y_unsave') : $r('app.string.a11y_save'),
          () => SavedPlaces.toggle(place))
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

  private isSaved(id: string): boolean {
    return this.saved.some((p: Place) => p.id === id);
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
