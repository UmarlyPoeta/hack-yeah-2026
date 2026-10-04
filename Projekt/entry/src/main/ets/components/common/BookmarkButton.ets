// Bookmark button over a photo. Saving squeezes the button, springs it back and sends out a square
// accent ring; removing only squeezes it.
import { curves } from '@kit.ArkUI';
import { Place } from '../../model/Place';
import { SavedPlaces } from '../../store/SavedPlaces';

@Component
export struct BookmarkButton {
  @Prop place: Place;
  @StorageLink('saved') saved: Place[] = [];
  @State private iconScale: number = 1;
  @State private ringScale: number = 1;
  @State private ringOpacity: number = 0;

  build() {
    Stack() {
      // the ring behind the button
      Row()
        .width($r('app.float.square_button_size'))
        .height($r('app.float.square_button_size'))
        .border({ width: 2, color: $r('app.color.accent_bright'), radius: $r('app.float.radius') })
        .scale({ x: this.ringScale, y: this.ringScale })
        .opacity(this.ringOpacity)
        .hitTestBehavior(HitTestMode.None)

      Button({ type: ButtonType.Normal }) {
        Image(this.isSaved() ? $r('app.media.ic_bookmark_light_on') : $r('app.media.ic_bookmark_light'))
          .width(20)
          .height(20)
          .scale({ x: this.iconScale, y: this.iconScale })
      }
      .width($r('app.float.square_button_size'))
      .height($r('app.float.square_button_size'))
      .borderRadius($r('app.float.radius'))
      .backgroundColor($r('app.color.photo_button_bg'))
      .accessibilityText(this.isSaved() ? $r('app.string.a11y_unsave') : $r('app.string.a11y_save'))
      .onClick(() => this.toggle())
    }
  }

  private isSaved(): boolean {
    return this.saved.some((p: Place) => p.id === this.place.id);
  }

  private toggle(): void {
    const saving = !this.isSaved();
    SavedPlaces.toggle(this.place);
    const ui = this.getUIContext();
    ui.animateTo({ duration: 90, curve: Curve.EaseIn, onFinish: () => {
      ui.animateTo({ curve: curves.springMotion(0.35, 0.45) }, () => {
        this.iconScale = 1;
      });
    } }, () => {
      this.iconScale = 0.6;
    });
    if (saving) {
      this.ringScale = 1;
      this.ringOpacity = 1;
      ui.animateTo({ duration: 450, curve: Curve.EaseOut }, () => {
        this.ringScale = 1.7;
        this.ringOpacity = 0;
      });
    }
  }
}
