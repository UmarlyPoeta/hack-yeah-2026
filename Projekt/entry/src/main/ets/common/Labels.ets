import { UIContext } from '@kit.ArkUI';

/**
 * "1 miejsce", "2 miejsca", "6 miejsc". Polish plural rule in code, because resource plurals follow
 * the device language and the texts of this app are Polish whatever the device language is.
 */
export function placesLabel(ui: UIContext, n: number): string {
  const ctx = ui.getHostContext();
  if (ctx === undefined) {
    return `${n}`;
  }
  const res = n === 1 ? $r('app.string.places_one')
    : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14)) ? $r('app.string.places_few')
      : $r('app.string.places_many');
  return ctx.resourceManager.getStringSync(res.id, n);
}
