import { GeoFix } from '../model/GeoPoint';
import { bearingDeg, distanceM } from './geo';

// Turns raw location fixes into "how is the user walking": position, speed, heading and
// whether they are moving or standing. Pure logic: time comes from GeoFix.t, never from a clock.
// Algorithm: docs/ARCHITECTURE.md §2.1.

export enum MotionState {
  MOVING = 'MOVING',
  STOPPED = 'STOPPED'
}

export interface MotionSnapshot {
  position: GeoFix | null;    // last accepted fix, null before the first one
  speedMps: number;           // averaged over SPEED_WINDOW_MS
  headingDeg: number | null;  // null until the user has moved HEADING_BASELINE_M
  state: MotionState;
  acceptedFixes: number;
  rejectedFixes: number;
}

export const MAX_ACCURACY_M: number = 50;          // worse fixes are ignored
export const MAX_WALK_SPEED_MPS: number = 5;       // faster jumps are GPS glitches
export const SPEED_WINDOW_MS: number = 10000;      // speed = displacement over ~10 s
// 25 m rather than 15: with ±5 m GPS noise a 15 m baseline swings the heading by ±30°
export const HEADING_BASELINE_M: number = 25;      // heading from movement over >= 25 m
export const STOP_BELOW_MPS: number = 0.3;
export const MOVE_ABOVE_MPS: number = 0.6;
export const STOP_AFTER_MS: number = 8000;
const BUFFER_KEEP_MS: number = 60000;

export class MotionTracker {
  private fixes: GeoFix[] = [];               // accepted fixes, oldest first, last ~60 s
  private speedMps: number = 0;
  private headingDeg: number | null = null;
  private state: MotionState = MotionState.STOPPED;
  private slowSinceT: number | null = null;   // when speed first dropped below STOP_BELOW_MPS
  private accepted: number = 0;
  private rejected: number = 0;

  // Feeds one fix and returns the updated snapshot. A rejected fix leaves everything unchanged.
  update(fix: GeoFix): MotionSnapshot {
    if (!this.isPlausible(fix)) {
      this.rejected++;
      return this.snapshot();
    }
    this.accepted++;
    this.fixes.push(fix);
    this.updateSpeed(fix);
    this.updateHeading(fix);
    this.updateState(fix.t);
    this.trimBuffer(fix.t);
    return this.snapshot();
  }

  snapshot(): MotionSnapshot {
    const s: MotionSnapshot = {
      position: this.fixes.length > 0 ? this.fixes[this.fixes.length - 1] : null,
      speedMps: this.speedMps,
      headingDeg: this.headingDeg,
      state: this.state,
      acceptedFixes: this.accepted,
      rejectedFixes: this.rejected
    };
    return s;
  }

  private isPlausible(fix: GeoFix): boolean {
    if (!(fix.accuracyM <= MAX_ACCURACY_M)) {   // also rejects NaN
      return false;
    }
    if (this.fixes.length === 0) {
      return true;
    }
    const last = this.fixes[this.fixes.length - 1];
    const dtS = (fix.t - last.t) / 1000;
    if (dtS <= 0) {
      return false;
    }
    // A pedestrian cannot cover more than this, plus both fixes' uncertainty.
    // Without the accuracy slack, normal GPS jitter on 1 s fixes would look like a jump.
    const allowedM = MAX_WALK_SPEED_MPS * dtS + fix.accuracyM + last.accuracyM;
    return distanceM(last, fix) <= allowedM;
  }

  // Speed from net displacement over the window, not from summing fix-to-fix steps:
  // jitter while standing still adds up when summed but mostly cancels in displacement.
  private updateSpeed(fix: GeoFix): void {
    let from: GeoFix | null = null;
    for (let i = 0; i < this.fixes.length - 1; i++) {
      if (fix.t - this.fixes[i].t <= SPEED_WINDOW_MS) {
        from = this.fixes[i];
        break;
      }
    }
    if (from === null) {
      // the previous fix is older than the window: use it anyway, it is the best we have
      from = this.fixes.length >= 2 ? this.fixes[this.fixes.length - 2] : null;
    }
    if (from === null) {
      this.speedMps = 0;
      return;
    }
    this.speedMps = distanceM(from, fix) / ((fix.t - from.t) / 1000);
  }

  // Heading = bearing from the most recent fix that is at least HEADING_BASELINE_M away.
  // If there is none (user standing or just started), the last known heading is kept.
  private updateHeading(fix: GeoFix): void {
    for (let i = this.fixes.length - 2; i >= 0; i--) {
      if (distanceM(this.fixes[i], fix) >= HEADING_BASELINE_M) {
        this.headingDeg = bearingDeg(this.fixes[i], fix);
        return;
      }
    }
  }

  // Hysteresis: MOVING as soon as speed > MOVE_ABOVE_MPS,
  // STOPPED only after speed stayed below STOP_BELOW_MPS for STOP_AFTER_MS.
  private updateState(t: number): void {
    if (this.speedMps > MOVE_ABOVE_MPS) {
      this.state = MotionState.MOVING;
      this.slowSinceT = null;
      return;
    }
    if (this.speedMps >= STOP_BELOW_MPS) {
      this.slowSinceT = null;
      return;
    }
    if (this.slowSinceT === null) {
      this.slowSinceT = t;
    }
    if (t - this.slowSinceT >= STOP_AFTER_MS) {
      this.state = MotionState.STOPPED;
    }
  }

  private trimBuffer(t: number): void {
    while (this.fixes.length > 2 && t - this.fixes[0].t > BUFFER_KEEP_MS) {
      this.fixes.shift();
    }
  }
}
