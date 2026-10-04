// Home screen card (Form Kit): the nearest landmark from the queue with its photo and "Posłuchaj".
// The app pushes new data with formProvider.updateForm (store/Widgets.ets) whenever the queue changes.
import { formBindingData, FormExtensionAbility, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { readFormIds, writeFormIds } from './FormIds';
import { cardBindingData } from './WidgetData';

export default class PlaceFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const id = want.parameters?.['ohos.extra.param.key.form_identity'] as string | undefined;
    if (id !== undefined) {
      const ids = readFormIds(this.context.filesDir).filter((f: string) => f !== id);
      ids.push(id);
      writeFormIds(this.context.filesDir, ids);
    }
    return cardBindingData(this.context.filesDir);
  }

  onUpdateForm(formId: string): void {
    formProvider.updateForm(formId, cardBindingData(this.context.filesDir)).catch(() => {
      // the card was removed meanwhile
    });
  }

  onRemoveForm(formId: string): void {
    writeFormIds(this.context.filesDir, readFormIds(this.context.filesDir).filter((f: string) => f !== formId));
  }
}
