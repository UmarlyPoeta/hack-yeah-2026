// Small controls shared by the screens. Square corners on purpose (radius token = 2 vp).
import { Fonts } from '../../common/Fonts';

/** Square icon button over a photo or a dark map. */
@Builder
export function PhotoIconButton(icon: Resource, label: Resource, action: () => void) {
  Button({ type: ButtonType.Normal }) {
    Image(icon).width(20).height(20)
  }
  .width($r('app.float.square_button_size'))
  .height($r('app.float.square_button_size'))
  .borderRadius($r('app.float.radius'))
  .backgroundColor($r('app.color.photo_button_bg'))
  .accessibilityText(label)
  .onClick(action)
}

/** Full-width primary action. dark = black on light screens; otherwise white on photos and dark screens. */
@Builder
export function PrimaryButton(label: ResourceStr, dark: boolean, action: () => void) {
  Button({ type: ButtonType.Normal }) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize($r('app.float.font_button'))
        .fontFamily(Fonts.BOLD)
        .fontColor(dark ? $r('app.color.on_primary') : $r('app.color.text'))
      Image(dark ? $r('app.media.ic_arrow_right') : $r('app.media.ic_arrow_right_dark'))
        .width(18)
        .height(18)
    }
  }
  .width('100%')
  .height($r('app.float.button_primary_height'))
  .borderRadius($r('app.float.radius'))
  .backgroundColor(dark ? $r('app.color.button_primary') : $r('app.color.surface'))
  .onClick(action)
}

/** "tour" wordmark. */
@Builder
export function Logo(size: Resource, color: ResourceColor) {
  Text($r('app.string.brand_name'))
    .fontSize(size)
    .fontFamily(Fonts.EXTRABOLD)
    .fontColor(color)
    .letterSpacing(-1)
}
