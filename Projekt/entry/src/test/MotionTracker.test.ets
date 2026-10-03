import { describe, it, expect } from '@ohos/hypium';
import { MotionState, MotionTracker, MotionSnapshot } from '../main/ets/guide/MotionTracker';
import { angleDiffDeg } from '../main/ets/guide/geo';
import { fixAt, Noise } from './TestGeo';

export default function motionTrackerTest() {
  describe('motionTracker', () => {
    it('headingOnlyAfter25m', 0, () => {
      const m = new MotionTracker();
      m.update(fixAt(0, 0, 0));
      expect(m.update(fixAt(20, 0, 16)).headingDeg).assertNull();
      const h: number | null = m.update(fixAt(26, 0, 20)).headingDeg;
      expect(h !== null && Math.abs(angleDiffDeg(0, h)) < 2).assertTrue();
      const e: number | null = m.update(fixAt(26, 26, 40)).headingDeg;
      expect(e !== null && Math.abs(e - 90) < 5).assertTrue();
    });

    it('rejectsBadFixes', 0, () => {
      const m = new MotionTracker();
      m.update(fixAt(0, 0, 0));
      const before: MotionSnapshot = m.update(fixAt(5, 0, 4));
      expect(m.update(fixAt(6, 0, 5, 150)).rejectedFixes).assertEqual(1);  // accuracy 150 m
      expect(m.update(fixAt(300, 0, 6)).rejectedFixes).assertEqual(2);     // 300 m in 2 s
      expect(m.update(fixAt(6, 0, 3)).rejectedFixes).assertEqual(3);       // time went back
      expect(m.snapshot().speedMps).assertEqual(before.speedMps);
      expect(m.snapshot().acceptedFixes).assertEqual(2);
    });

    it('jitterIsNotAJump', 0, () => {
      const m = new MotionTracker();
      const n = new Noise(7);
      for (let t = 0; t < 30; t++) {
        m.update(fixAt(n.next() * 5, n.next() * 5, t));
      }
      expect(m.snapshot().rejectedFixes).assertEqual(0);
    });

    it('stopsAfter8sAndMovesImmediately', 0, () => {
      const m = new MotionTracker();
      let t = 0;
      for (let north = 0; north <= 60; north += 1.3) {
        m.update(fixAt(north, 0, t));
        t++;
      }
      expect(m.snapshot().state).assertEqual(MotionState.MOVING);
      const stopT = t;
      const n = new Noise(3);
      let stoppedAt = -1;
      for (let i = 0; i < 40; i++) {
        const s: MotionSnapshot = m.update(fixAt(60 + n.next() * 2, n.next() * 2, t));
        if (stoppedAt < 0 && s.state === MotionState.STOPPED) {
          stoppedAt = t;
        }
        t++;
      }
      expect(stoppedAt - stopT >= 8 && stoppedAt - stopT <= 22).assertTrue();
      let movingAfter = -1;
      for (let k = 1; k <= 10; k++) {
        if (movingAfter < 0 && m.update(fixAt(60 + k * 1.5, 0, t)).state === MotionState.MOVING) {
          movingAfter = k;
        }
        t++;
      }
      expect(movingAfter > 0 && movingAfter <= 6).assertTrue();
    });
  });
}
