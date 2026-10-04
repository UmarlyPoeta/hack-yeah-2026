// First launch only (Settings.onboarded): what tour is, interests, then location. The location fills the
// landmark queue, so the main screen is not empty; the app moves on once the first places are in.
import { common } from '@kit.AbilityKit';
import { Fonts, registerFonts } from '../common/Fonts';
import { Logo, PrimaryButton } from '../components/common/Controls';
import { GeoFix } from '../model/GeoPoint';
import { Place } from '../model/Place';
import { Interest } from '../model/Segment';
import { Notifier } from '../store/Notifier';
import { PlaceQueue } from '../store/PlaceQueue';
import { Settings } from '../store/Settings';
import { UserLocation } from '../store/UserLocation';
import { setStatusBarLight } from '../common/StatusBar';

// Used only when location is refused or unavailable, and said so on screen (ob_denied).
const FALLBACK_FIX: GeoFix = { lat: 50.0614, lon: 19.9372, accuracyM: 1000, t: 0 };
const PLACES_TO_START: number = 3;

const INTERESTS: Interest[] = [Interest.HISTORY, Interest.ARCHITECTURE, Interest.ART, Interest.PEOPLE, Interest.LEGENDS];

@Entry
@Component
struct OnboardingPage {
  @State step: number = 0;
  @State interests: string[] = [];
  @State searching: boolean = false;
  @State denied: boolean = false;
  @StorageProp('queue') @Watch('onQueue') queue: Place[] = [];
  @StorageProp('topInset') topInset: number = 0;
  @StorageProp('bottomInset') bottomInset: number = 0;
  private done: boolean = false;

  aboutToAppear(): void {
    registerFonts(this.getUIContext());
    this.interests = Settings.interests();
    setStatusBarLight(this.getUIContext().getHostContext(), true);
  }

  build() {
    Column() {
      if (this.step === 0) {
        this.Welcome()
      } else if (this.step === 1) {
        this.Interests()
      } else {
        this.Location()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.step === 0 ? $r('app.color.ink') : $r('app.color.surface'))
  }

  @Builder
  StepLabel(light: boolean) {
    Text(this.getUIContext().getHostContext()?.resourceManager.getStringSync($r('app.string.ob_step').id, this.step + 1) ?? '')
      .fontSize($r('app.float.font_caption'))
      .fontFamily(Fonts.BOLD)
      .letterSpacing(1)
      .fontColor(light ? $r('app.color.on_ink_secondary') : $r('app.color.text_secondary'))
  }

  @Builder
  Welcome() {
    Column() {
      this.StepLabel(true)
      Blank()
      Logo($r('app.float.font_logo'), $r('app.color.on_ink'))
      Text($r('app.string.ob_tagline'))
        .fontSize($r('app.float.font_fact'))
        .lineHeight(28)
        .fontFamily(Fonts.SEMIBOLD)
        .fontColor($r('app.color.on_ink'))
        .margin({ top: 16 })
      Text($r('app.string.ob_welcome_body'))
        .fontSize($r('app.float.font_body'))
        .lineHeight(22)
        .fontFamily(Fonts.REGULAR)
        .fontColor($r('app.color.on_ink_secondary'))
        .margin({ top: 12 })
      Row()
        .width(40)
        .height(2)
        .backgroundColor($r('app.color.accent_bright'))
        .margin({ top: 24, bottom: 32 })
      PrimaryButton($r('app.string.ob_next'), false, () => this.go(1))
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 24, right: 24, top: this.topInset + 20, bottom: this.bottomInset + 24 })
  }

  @Builder
  Interests() {
    Column() {
      this.StepLabel(false)
      Text($r('app.string.ob_interests_title'))
        .fontSize($r('app.float.font_hero_title'))
        .fontFamily(Fonts.EXTRABOLD)
        .fontColor($r('app.color.text'))
        .letterSpacing(-0.6)
        .margin({ top: 32 })
      Text($r('app.string.ob_interests_body'))
        .fontSize($r('app.float.font_body'))
        .lineHeight(22)
        .fontFamily(Fonts.REGULAR)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })

      Column({ space: 8 }) {
        ForEach(INTERESTS, (interest: Interest) => {
          this.InterestRow(interest)
        }, (interest: Interest) => interest)
      }
      .width('100%')
      .margin({ top: 28 })

      Blank()
      PrimaryButton($r('app.string.ob_next'), true, () => {
        Settings.setInterests(this.interests);
        this.go(2);
      })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 24, right: 24, top: this.topInset + 20, bottom: this.bottomInset + 24 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 250 }))
  }

  @Builder
  InterestRow(interest: Interest) {
    Row() {
      Text(this.interestLabel(interest))
        .fontSize($r('app.float.font_button'))
        .fontFamily(Fonts.BOLD)
        .fontColor(this.isOn(interest) ? $r('app.color.accent_on_bg') : $r('app.color.text'))
      Blank()
      Row()
        .width(14)
        .height(14)
        .borderRadius($r('app.float.radius'))
        .border({ width: 2, color: this.isOn(interest) ? $r('app.color.accent') : $r('app.color.separator') })
        .backgroundColor(this.isOn(interest) ? $r('app.color.accent') : Color.Transparent)
    }
    .width('100%')
    .height($r('app.float.button_primary_height'))
    .padding({ left: 16, right: 16 })
    .borderRadius($r('app.float.radius'))
    .backgroundColor(this.isOn(interest) ? $r('app.color.accent_bg') : $r('app.color.surface'))
    .border({
      width: 1,
      color: this.isOn(interest) ? $r('app.color.accent') : $r('app.color.separator'),
      radius: $r('app.float.radius')
    })
    .animation({ duration: 150 })
    .accessibilityChecked(this.isOn(interest))
    .onClick(() => this.toggle(interest))
  }

  @Builder
  Location() {
    Column() {
      this.StepLabel(false)
      Text($r('app.string.ob_location_title'))
        .fontSize($r('app.float.font_hero_title'))
        .fontFamily(Fonts.EXTRABOLD)
        .fontColor($r('app.color.text'))
        .letterSpacing(-0.6)
        .margin({ top: 32 })
      Text($r('app.string.ob_location_body'))
        .fontSize($r('app.float.font_body'))
        .lineHeight(22)
        .fontFamily(Fonts.REGULAR)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })

      if (this.denied) {
        Text($r('app.string.ob_denied'))
          .fontSize($r('app.float.font_label'))
          .lineHeight(20)
          .fontFamily(Fonts.MEDIUM)
          .fontColor($r('app.color.accent_on_bg'))
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.accent_bg'))
          .border({ width: { left: 2 }, color: { left: $r('app.color.accent') } })
          .margin({ top: 20 })
      }

      Blank()

      if (this.searching) {
        Row({ space: 12 }) {
          LoadingProgress().width(24).height(24).color($r('app.color.accent'))
          Text($r('app.string.ob_searching'))
            .fontSize($r('app.float.font_body'))
            .fontFamily(Fonts.SEMIBOLD)
            .fontColor($r('app.color.text'))
            .layoutWeight(1)
          Text(`${Math.min(this.queue.length, PLACES_TO_START)} / ${PLACES_TO_START}`)
            .fontSize($r('app.float.font_small'))
            .fontFamily(Fonts.BOLD)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .height($r('app.float.button_primary_height'))
      } else {
        PrimaryButton($r('app.string.ob_allow'), true, () => this.locate())
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 24, right: 24, top: this.topInset + 20, bottom: this.bottomInset + 24 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 250 }))
  }

  private go(step: number): void {
    setStatusBarLight(this.getUIContext().getHostContext(), step === 0);
    this.getUIContext().animateTo({ duration: 250 }, () => {
      this.step = step;
    });
  }

  private isOn(interest: Interest): boolean {
    return this.interests.includes(interest);
  }

  private toggle(interest: Interest): void {
    this.interests = this.isOn(interest) ? this.interests.filter((i: string) => i !== interest) :
      this.interests.concat([interest]);
  }

  private interestLabel(interest: Interest): string {
    const ctx = this.getUIContext().getHostContext();
    return ctx === undefined ? interest : ctx.resourceManager.getStringByNameSync(`interest_${interest}`);
  }

  private async locate(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const granted = await UserLocation.requestPermission(ctx);
    await Notifier.enable(ctx);
    this.searching = true;
    let fix: GeoFix | null = granted ? await UserLocation.current() : null;
    if (fix === null) {
      this.denied = true;
      fix = FALLBACK_FIX;
      AppStorage.setOrCreate<number>('userLat', fix.lat);
      AppStorage.setOrCreate<number>('userLon', fix.lon);
    }
    await PlaceQueue.refill(fix);
    this.finish();   // also when the server found fewer places: the main screen keeps looking
  }

  onQueue(): void {
    if (this.searching && this.queue.length >= PLACES_TO_START) {
      this.finish();
    }
  }

  private finish(): void {
    if (this.done) {
      return;
    }
    this.done = true;
    Settings.finishOnboarding();
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/MainPage' });
  }
}
