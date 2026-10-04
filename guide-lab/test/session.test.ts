import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FIRST_FIX_TIMEOUT_MS, LOCATION_SWITCH_OFF_CODE, SessionReason, SessionState, WalkSession } from '../src/session/WalkSession';

test('happy path: ask, grant, first fix, walk', () => {
  const s = new WalkSession();
  assert.ok(s.start(0));
  assert.equal(s.state, SessionState.ASKING);
  assert.ok(s.permissionResult(true, 100));
  assert.equal(s.state, SessionState.ACQUIRING);
  assert.ok(s.wantsLocation());
  assert.ok(s.fix(2000));
  assert.equal(s.state, SessionState.WALKING);
  assert.equal(s.fix(3000), false, 'more fixes change nothing');
});

test('denied permission and missing first fix are errors with a reason', () => {
  const a = new WalkSession();
  a.start(0);
  a.permissionResult(false, 10);
  assert.deepEqual([a.state, a.reason], [SessionState.ERROR, SessionReason.DENIED]);
  assert.equal(a.wantsLocation(), false);
  const b = new WalkSession();
  b.start(0);
  b.permissionResult(true, 0);
  assert.equal(b.tick(FIRST_FIX_TIMEOUT_MS - 1), false);
  assert.ok(b.tick(FIRST_FIX_TIMEOUT_MS));
  assert.deepEqual([b.state, b.reason], [SessionState.ERROR, SessionReason.NO_FIX]);
});

test('location switched off: error before walking, pause while walking', () => {
  const a = new WalkSession();
  a.start(0);
  a.permissionResult(true, 0);
  a.locationError(LOCATION_SWITCH_OFF_CODE, 10);
  assert.deepEqual([a.state, a.reason], [SessionState.ERROR, SessionReason.LOCATION_OFF]);
  const b = new WalkSession();
  b.start(0);
  b.permissionResult(true, 0);
  b.fix(1);
  b.locationError(LOCATION_SWITCH_OFF_CODE, 10);
  assert.deepEqual([b.state, b.reason], [SessionState.PAUSED, SessionReason.LOCATION_OFF]);
});

test('background pauses; resume asks again (the one-time grant is gone)', () => {
  const s = new WalkSession();
  s.start(0);
  s.permissionResult(true, 0);
  s.fix(1);
  assert.ok(s.background(100));
  assert.deepEqual([s.state, s.reason], [SessionState.PAUSED, SessionReason.BACKGROUND]);
  assert.equal(s.wantsLocation(), false);
  assert.ok(s.resume(200));
  assert.equal(s.state, SessionState.ASKING);
  assert.equal(s.background(300), false, 'nothing to pause while asking');
  s.stop(400);
  assert.equal(s.state, SessionState.IDLE);
});
