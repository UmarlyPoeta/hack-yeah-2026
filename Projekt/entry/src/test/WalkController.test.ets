import { describe, it, expect } from '@ohos/hypium';
import { Segment, SegmentKind } from '../main/ets/model/Segment';
import { Clock, NarrationOutput, WalkController } from '../main/ets/viewmodel/WalkController';
import { poiAt, standAt, walkNorth } from './TestGeo';
import { GeoFix } from '../main/ets/model/GeoPoint';

class FakeClock implements Clock {
  t: number = 0;
  now(): number {
    return this.t;
  }
}

class FakeOutput implements NarrationOutput {
  played: Segment[] = [];
  stopped: number = 0;
  play(segment: Segment): void {
    this.played.push(segment);
  }
  stop(): void {
    this.stopped++;
  }
}

function drive(c: WalkController, clock: FakeClock, fixes: GeoFix[]): void {
  for (let i = 0; i < fixes.length; i++) {
    clock.t = fixes[i].t;
    c.onFix(fixes[i]);
    const end = i + 1 < fixes.length ? fixes[i + 1].t : fixes[i].t;
    for (let t = fixes[i].t + 1000; t < end; t += 1000) {
      clock.t = t;
      c.tick();
    }
  }
}

export default function walkControllerTest() {
  describe('walkController', () => {
    it('offlineDeepDiveFlow', 0, () => {
      const clock = new FakeClock();
      const out = new FakeOutput();
      const c = new WalkController([poiAt('Sukiennice', 60, 10, 0.9)], [], null, out, clock);
      drive(c, clock, walkNorth(0, 62, 0).concat(standAt(62, 48, 40)));
      expect(c.state().originLabel).assertEqual('szablon');
      expect(c.state().deepDiveOfferId).assertEqual('Sukiennice');
      c.acceptDeepDive();
      for (let k = 0; k < 10; k++) {
        clock.t += 1000;
        c.tick();
      }
      expect(out.played[out.played.length - 1].kind).assertEqual(SegmentKind.DEEP_DIVE);
      expect(c.state().deepDiveOfferId).assertEqual('');
    });

    it('nextStopOnScreen', 0, () => {
      const clock = new FakeClock();
      const c = new WalkController([poiAt('A', 150, 0, 0.9), poiAt('B', 260, 0, 0.9)], [], null, new FakeOutput(), clock);
      drive(c, clock, walkNorth(0, 40, 0));
      expect(c.state().nextPoiName).assertEqual('A');
      expect(c.state().laterStops.join(',')).assertEqual('B');
      expect(Math.abs(c.state().bearingAngle) < 10).assertTrue();
    });

    it('pauseStopsNarrator', 0, () => {
      const out = new FakeOutput();
      new WalkController([], [], null, out, new FakeClock()).pause();
      expect(out.stopped).assertEqual(1);
    });
  });
}
