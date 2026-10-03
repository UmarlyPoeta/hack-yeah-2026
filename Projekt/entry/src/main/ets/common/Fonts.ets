import { UIContext } from '@kit.ArkUI';

// Manrope (SIL Open Font License, rawfile/fonts/), static weights registered once for the whole app.
export class Fonts {
  static readonly REGULAR: string = 'ManropeRegular';
  static readonly MEDIUM: string = 'ManropeMedium';
  static readonly SEMIBOLD: string = 'ManropeSemiBold';
  static readonly BOLD: string = 'ManropeBold';
  static readonly EXTRABOLD: string = 'ManropeExtraBold';
}

let registered: boolean = false;

export function registerFonts(ui: UIContext): void {
  if (registered) {
    return;
  }
  const font = ui.getFont();
  font.registerFont({ familyName: Fonts.REGULAR, familySrc: $rawfile('fonts/Manrope-Regular.ttf') });
  font.registerFont({ familyName: Fonts.MEDIUM, familySrc: $rawfile('fonts/Manrope-Medium.ttf') });
  font.registerFont({ familyName: Fonts.SEMIBOLD, familySrc: $rawfile('fonts/Manrope-SemiBold.ttf') });
  font.registerFont({ familyName: Fonts.BOLD, familySrc: $rawfile('fonts/Manrope-Bold.ttf') });
  font.registerFont({ familyName: Fonts.EXTRABOLD, familySrc: $rawfile('fonts/Manrope-ExtraBold.ttf') });
  registered = true;
}
