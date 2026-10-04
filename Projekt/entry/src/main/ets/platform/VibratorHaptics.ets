import { vibrator } from '@kit.SensorServiceKit';
import { HapticCue, HapticOutput, patternFor } from '../viewmodel/Haptics';

// Plays a HapticCue as a sequence of pulses (issue #52). Needs ohos.permission.VIBRATE (no dialog).
// On the emulator nothing is felt; the cue is still logged.
export class VibratorHaptics implements HapticOutput {
  enabled: boolean = true;

  cue(cue: HapticCue): void {
    console.info('haptic cue ' + cue);
    if (!this.enabled) {
      return;
    }
    const pattern = patternFor(cue);
    let at = 0;
    for (let i = 0; i < pattern.length; i += 2) {
      const duration = pattern[i];
      setTimeout(() => this.pulse(duration), at);
      at += duration + (i + 1 < pattern.length ? pattern[i + 1] : 0);
    }
  }

  private pulse(duration: number): void {
    const effect: vibrator.VibrateTime = { type: 'time', duration: duration };
    const attribute: vibrator.VibrateAttribute = { id: 0, usage: 'notification' };
    vibrator.startVibration(effect, attribute).catch((e: Error) => {
      console.error('vibration failed: ' + e.message);
    });
  }
}
