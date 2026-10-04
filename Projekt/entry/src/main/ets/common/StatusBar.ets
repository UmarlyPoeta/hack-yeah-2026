import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

/** light = white status bar icons (over photos and dark screens), else dark icons. */
export function setStatusBarLight(context: common.Context | undefined, light: boolean): void {
  if (context === undefined) {
    return;
  }
  window.getLastWindow(context).then((win: window.Window) => {
    win.setWindowSystemBarProperties({ statusBarContentColor: light ? '#FFFFFF' : '#1C1C1E' });
  }).catch(() => {
    // no window yet: keep the system default
  });
}
