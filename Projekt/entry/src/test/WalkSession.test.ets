import { describe, it, expect } from '@ohos/hypium';
import { FIRST_FIX_TIMEOUT_MS, LOCATION_SWITCH_OFF_CODE, SessionReason, SessionState, WalkSession } from '../main/ets/session/WalkSession';

export default function walkSessionTest() {
  describe('walkSession', () => {
    it('happyPath', 0, () => {
      const s = new WalkSession();
      s.start(0);
      s.permissionResult(true, 10);
      expect(s.state).assertEqual(SessionState.ACQUIRING);
      s.fix(20);
      expect(s.state).assertEqual(SessionState.WALKING);
    });
    it('deniedAndNoFix', 0, () => {
      const a = new WalkSession();
      a.start(0);
      a.permissionResult(false, 0);
      expect(a.reason).assertEqual(SessionReason.DENIED);
      const b = new WalkSession();
      b.start(0);
      b.permissionResult(true, 0);
      b.tick(FIRST_FIX_TIMEOUT_MS);
      expect(b.reason).assertEqual(SessionReason.NO_FIX);
    });
    it('backgroundAndLocationOff', 0, () => {
      const s = new WalkSession();
      s.start(0);
      s.permissionResult(true, 0);
      s.fix(1);
      s.locationError(LOCATION_SWITCH_OFF_CODE, 2);
      expect(s.reason).assertEqual(SessionReason.LOCATION_OFF);
      s.resume(3);
      expect(s.state).assertEqual(SessionState.ASKING);
      s.permissionResult(true, 4);
      s.fix(5);
      s.background(6);
      expect(s.state).assertEqual(SessionState.PAUSED);
      expect(s.wantsLocation()).assertFalse();
    });
  });
}
