import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MotionState, MotionTracker, MotionSnapshot } from '../src/guide/MotionTracker';
import { angleDiffDeg } from '../src/guide/geo';
import { demoRoute, fixAt, Noise } from './helpers';

test('demo route: starts STOPPED without heading, then walks at ~1.3 m/s', () => {
  const m = new MotionTracker();
  const route = demoRoute();
  const first = m.update(route[0]);
  assert.equal(first.state, MotionState.STOPPED);
  assert.equal(first.headingDeg, null);
  let s: MotionSnapshot = first;
  for (let i = 1; i < route.length; i++) {
    s = m.update(route[i]);
    if (i >= 4) {   // heading needs 25 m, i.e. 4 route points
      assert.equal(s.state, MotionState.MOVING, `fix ${i}`);
      assert.ok(Math.abs(s.speedMps - 1.3) < 0.1, `fix ${i} speed ${s.speedMps}`);
      assert.notEqual(s.headingDeg, null);
    }
  }
  assert.equal(s.rejectedFixes, 0);
});

test('heading appears only after moving 25 m, pointing the right way', () => {
  const m = new MotionTracker();
  m.update(fixAt(0, 0, 0));
  assert.equal(m.update(fixAt(5, 0, 4)).headingDeg, null);
  assert.equal(m.update(fixAt(10, 0, 8)).headingDeg, null);
  assert.equal(m.update(fixAt(20, 0, 16)).headingDeg, null);
  const h = m.update(fixAt(26, 0, 20)).headingDeg;   // walking north
  assert.ok(h !== null && (h < 2 || h > 358), `heading ${h}`);
  const e = m.update(fixAt(26, 26, 40)).headingDeg;  // turned east
  assert.ok(e !== null && Math.abs(e - 90) < 5, `heading ${e}`);
});

test('bad fixes are rejected and change nothing', () => {
  const m = new MotionTracker();
  m.update(fixAt(0, 0, 0));
  const before = m.update(fixAt(5, 0, 4));
  assert.equal(m.update(fixAt(6, 0, 5, 150)).rejectedFixes, 1);  // accuracy 150 m
  assert.equal(m.update(fixAt(300, 0, 6)).rejectedFixes, 2);     // 300 m in 2 s
  assert.equal(m.update(fixAt(6, 0, 3)).rejectedFixes, 3);       // time went back
  const after = m.snapshot();
  assert.deepEqual(after.position, before.position);
  assert.equal(after.speedMps, before.speedMps);
  assert.equal(after.acceptedFixes, 2);
});

test('normal 1 Hz jitter of a few metres is not mistaken for a jump', () => {
  const m = new MotionTracker();
  const n = new Noise(7);
  for (let t = 0; t < 30; t++) {
    m.update(fixAt(n.next() * 5, n.next() * 5, t));
  }
  assert.equal(m.snapshot().rejectedFixes, 0);
});

test('stopping: STOPPED only after 8 s of slow speed, heading kept; moving again is immediate', () => {
  const m = new MotionTracker();
  let t = 0;
  for (let north = 0; north <= 60; north += 1.3) {   // walk north 1.3 m/s, 1 Hz
    m.update(fixAt(north, 0, t));
    t++;
  }
  const walkingHeading = m.snapshot().headingDeg;
  const stopT = t;
  const n = new Noise(3);
  let stoppedAt = -1;
  for (let i = 0; i < 40; i++) {                       // stand still with ±2 m jitter
    const s = m.update(fixAt(60 + n.next() * 2, n.next() * 2, t));
    if (stoppedAt < 0 && s.state === MotionState.STOPPED) {
      stoppedAt = t;
    }
    t++;
  }
  assert.ok(stoppedAt - stopT >= 8, `stopped too early: ${stoppedAt - stopT} s`);
  assert.ok(stoppedAt - stopT <= 22, `stopped too late: ${stoppedAt - stopT} s`);
  const h = m.snapshot().headingDeg;
  assert.ok(h !== null && walkingHeading !== null && Math.abs(angleDiffDeg(walkingHeading, h)) < 30,
    `heading drifted from ${walkingHeading} to ${h}`);
  // walk off again: MOVING within a few seconds
  let movingAfter = -1;
  for (let k = 1; k <= 10; k++) {
    if (m.update(fixAt(60 + k * 1.5, 0, t)).state === MotionState.MOVING && movingAfter < 0) {
      movingAfter = k;
    }
    t++;
  }
  assert.ok(movingAfter > 0 && movingAfter <= 6, `moving after ${movingAfter} s`);
});
