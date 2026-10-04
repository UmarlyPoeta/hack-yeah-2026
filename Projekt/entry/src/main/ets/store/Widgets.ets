// Refreshes the home screen cards (widget/PlaceFormAbility.ets) after the queue changed.
import { common } from '@kit.AbilityKit';
import { formProvider } from '@kit.FormKit';
import { readFormIds, writeFormIds } from '../widget/FormIds';
import { cardBindingData } from '../widget/WidgetData';

export class Widgets {
  static update(context: common.Context): void {
    const ids = readFormIds(context.filesDir);
    for (const id of ids) {
      formProvider.updateForm(id, cardBindingData(context.filesDir)).catch(() => {
        // the user removed this card: forget it
        writeFormIds(context.filesDir, readFormIds(context.filesDir).filter((f: string) => f !== id));
      });
    }
  }
}
