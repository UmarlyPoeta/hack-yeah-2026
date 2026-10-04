import { Side } from '../guide/Itinerary';

// Wrist cues that tell where to look without looking at a screen (issue #52).
export enum HapticCue {
  LOOK_LEFT = 'LOOK_LEFT',
  LOOK_RIGHT = 'LOOK_RIGHT',
  LOOK_AHEAD = 'LOOK_AHEAD',
  ARRIVED = 'ARRIVED'
}

// Vibration pattern: alternating on/off durations in ms, starting with "on".
export function patternFor(cue: HapticCue): number[] {
  if (cue === HapticCue.LOOK_LEFT) {
    return [120, 120, 120];         // two short
  }
  if (cue === HapticCue.LOOK_RIGHT) {
    return [450];                   // one long
  }
  if (cue === HapticCue.ARRIVED) {
    return [80, 80, 80, 80, 300];   // double tap, then a longer pulse
  }
  return [120];                     // one short: straight ahead
}

export function cueForSide(side: Side): HapticCue {
  return side === Side.LEFT ? HapticCue.LOOK_LEFT : (side === Side.RIGHT ? HapticCue.LOOK_RIGHT : HapticCue.LOOK_AHEAD);
}

// Platform port: VibratorHaptics.ets on the device, a fake in tests.
export interface HapticOutput {
  cue(cue: HapticCue): void;
}
