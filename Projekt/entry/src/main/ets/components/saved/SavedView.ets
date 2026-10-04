// "Moje" tab: landmarks saved for later (SavedPlaces, newest first) and the settings:
// hands-free mode (off by default, someone switches it on for the person) and the reset.
import { Fonts } from '../../common/Fonts';
import { Place, placeImage, shortName } from '../../model/Place';
import { CityInfo } from '../../store/CityInfo';
import { Guide } from '../../store/Guide';
import { HandsFree } from '../../store/HandsFree';
import { Notifier } from '../../store/Notifier';
import { PlaceQueue } from '../../store/PlaceQueue';
import { SavedPlaces } from '../../store/SavedPlaces';
import { Settings } from '../../store/Settings';
import { Widgets } from '../../store/Widgets';

@Component
export struct SavedView {
  onOpen: (place: Place) => void = () => {};
  @StorageLink('saved') saved: Place[] = [];
  @StorageProp('handsFree') handsFree: boolean = false;
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

      Scroll() {
        Column() {
          this.SectionTitle($r('app.string.section_saved'))
          if (this.saved.length === 0) {
            Text($r('app.string.saved_empty_short'))
              .fontSize($r('app.float.font_label'))
              .fontFamily(Fonts.REGULAR)
              .fontColor($r('app.color.text_secondary'))
              .padding({ top: 8, bottom: 8 })
          } else {
            ForEach(this.saved, (place: Place) => {
              this.Row(place)
              Divider().color($r('app.color.separator'))
            }, (place: Place) => place.id)
          }

          this.SectionTitle($r('app.string.section_settings'))
          this.HandsFreeRow()
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .margin({ top: 8 })

      Text($r('app.string.reset'))
        .fontSize($r('app.float.font_caption'))
        .fontFamily(Fonts.SEMIBOLD)
        .fontColor($r('app.color.text_muted'))
        .constraintSize({ minHeight: $r('app.float.touch_min') })
        .alignSelf(ItemAlign.Center)
        .margin({ bottom: 4 })
        .onClick(() => this.confirmReset())
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
    .accessibilityText(shortName(place))
    .onClick(() => this.onOpen(place))
  }

  private confirmReset(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.reset_title'),
      message: $r('app.string.reset_body'),
      autoCancel: true,
      primaryButton: { value: $r('app.string.cancel'), action: () => {} },
      secondaryButton: {
        value: $r('app.string.reset_confirm'),
        fontColor: $r('app.color.danger'),
        action: () => this.reset(),
      },
    });
  }

  /** Everything back to the first launch: settings, queue with photos, saved places, town, notification. */
  private reset(): void {
    Guide.stop();
    HandsFree.reset();
    Notifier.reset();
    SavedPlaces.reset();
    PlaceQueue.reset();
    CityInfo.reset();
    Settings.reset();
    const ctx = this.getUIContext().getHostContext();
    if (ctx !== undefined) {
      Widgets.update(ctx);   // home screen card back to "Szukam zabytków"
    }
    const router = this.getUIContext().getRouter();
    router.clear();
    router.replaceUrl({ url: 'pages/OnboardingPage' });
  }

  @Builder
  SectionTitle(title: Resource) {
    Text(title)
      .fontSize($r('app.float.font_caption'))
      .fontFamily(Fonts.BOLD)
      .fontColor($r('app.color.accent'))
      .letterSpacing(1.5)
      .textCase(TextCase.UpperCase)
      .margin({ top: 24, bottom: 4 })
      .accessibilityLevel('yes')
  }

  // Off by default: someone switches it on for the person who will not look at the screen.
  @Builder
  HandsFreeRow() {
    Row({ space: 16 }) {
      Column({ space: 4 }) {
        Text($r('app.string.hands_free'))
          .fontSize($r('app.float.font_body'))
          .fontFamily(Fonts.BOLD)
          .fontColor($r('app.color.text'))
        Text($r('app.string.hands_free_body'))
          .fontSize($r('app.float.font_small'))
          .lineHeight(18)
          .fontFamily(Fonts.REGULAR)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.handsFree })
        .selectedColor($r('app.color.accent'))
        .accessibilityText($r('app.string.hands_free'))
        .onChange((on: boolean) => {
          Settings.setHandsFree(on);
          if (!on) {
            HandsFree.stop();
          }
          Guide.restartTimer();
        })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

}
