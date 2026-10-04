import { emitter } from '@kit.BasicServicesKit';

// EntryAbility → view models: the app went to the background / came back. With a one-time location
// grant, going to the background ends the walk's location access, so the walk must pause.
export const APP_BACKGROUND_EVENT: string = 'spacer.app.background';
export const APP_FOREGROUND_EVENT: string = 'spacer.app.foreground';

export function emitAppBackground(): void {
  emitter.emit(APP_BACKGROUND_EVENT);
}

export function emitAppForeground(): void {
  emitter.emit(APP_FOREGROUND_EVENT);
}

// Debug commands sent with `aa start ... --ps action <name>` (GuideDebugPage listens).
export const DEBUG_ACTION_EVENT: string = 'spacer.debug.action';

export function emitDebugAction(action: string): void {
  const data: emitter.EventData = { data: { 'action': action } };
  emitter.emit(DEBUG_ACTION_EVENT, data);
}
