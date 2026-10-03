import { curves, UIContext } from '@kit.ArkUI';

// Visual language: a printed museum walking guide. Warm paper, ink, Kraków brick as the only accent.
export class Palette {
  static readonly PAPER: string = '#F3EEE4';
  static readonly PAPER_DEEP: string = '#E8E0D1';
  static readonly CARD: string = '#FBF8F2';
  static readonly INK: string = '#1E1A16';
  static readonly INK_SOFT: string = '#5B534A';
  static readonly INK_FAINT: string = '#958B7F';
  static readonly RULE: string = '#D8CDBB';
  static readonly BRICK: string = '#A23B26';
  static readonly BRICK_SOFT: string = '#EBD7CC';
  static readonly MOSS: string = '#4F6B4A';
  static readonly AMBER: string = '#B07A26';
  static readonly SCRIM: string = '#661E1A16';
}

// Newsreader (SIL Open Font License, rawfile/fonts/), static instances registered in EntryAbility.
export class Fonts {
  static readonly TEXT: string = 'NewsreaderText';
  static readonly TEXT_MEDIUM: string = 'NewsreaderTextMedium';
  static readonly DISPLAY: string = 'NewsreaderDisplay';
  static readonly ITALIC: string = 'NewsreaderItalic';
}

let fontsRegistered: boolean = false;

/** Registers the bundled fonts once for the whole app; call from the first page. */
export function registerFonts(ui: UIContext): void {
  if (fontsRegistered) {
    return;
  }
  const font = ui.getFont();
  font.registerFont({ familyName: Fonts.TEXT, familySrc: $rawfile('fonts/Newsreader-Text.ttf') });
  font.registerFont({ familyName: Fonts.TEXT_MEDIUM, familySrc: $rawfile('fonts/Newsreader-TextMedium.ttf') });
  font.registerFont({ familyName: Fonts.DISPLAY, familySrc: $rawfile('fonts/Newsreader-Display.ttf') });
  font.registerFont({ familyName: Fonts.ITALIC, familySrc: $rawfile('fonts/Newsreader-Italic.ttf') });
  fontsRegistered = true;
}

/** Small uppercase label with tracking (sans, system font). */
@Builder
export function Eyebrow(text: string, color: string = Palette.INK_FAINT) {
  Text(text)
    .fontSize(11)
    .fontWeight(FontWeight.Medium)
    .letterSpacing(1.6)
    .fontColor(color)
}

/** Thin horizontal rule. */
@Builder
export function Rule() {
  Divider()
    .strokeWidth(1)
    .color(Palette.RULE)
}

// Motion: calm and short. One easing for everything that enters, staggered by STAGGER_MS.
export class Motion {
  static readonly ENTER_MS: number = 650;
  static readonly STAGGER_MS: number = 70;
  static readonly ENTER_SHIFT: number = 18;
  static readonly EASE_OUT: ICurve = curves.cubicBezierCurve(0.16, 1, 0.3, 1);
}
