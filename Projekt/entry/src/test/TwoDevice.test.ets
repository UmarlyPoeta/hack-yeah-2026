import { describe, it, expect } from '@ohos/hypium';
import { GeoFix } from '../main/ets/model/GeoPoint';
import { Poi } from '../main/ets/model/Poi';
import { Segment, SegmentKind } from '../main/ets/model/Segment';
import { DeviceLink, LinkMessage } from '../main/ets/link/DeviceLink';
import { HapticCue, HapticOutput } from '../main/ets/viewmodel/Haptics';
import { Clock, DeviceRole, NarrationOutput, WalkController } from '../main/ets/viewmodel/WalkController';
import { poiAt, walkNorth } from './TestGeo';

class FakeClock implements Clock {
  t: number = 0;
  now(): number {
    return this.t;
  }
}

class FakeOutput implements NarrationOutput {
  played: Segment[] = [];
  play(segment: Segment): void {
    this.played.push(segment);
  }
  stop(): void {
  }
}

class FakeHaptics implements HapticOutput {
  cues: HapticCue[] = [];
  cue(c: HapticCue): void {
    this.cues.push(c);
  }
}

class LinkEnd implements DeviceLink {
  peer: LinkEnd | null = null;
  inbox: LinkMessage[] = [];
  listener: ((m: LinkMessage) => void) | null = null;
  send(m: LinkMessage): void {
    if (this.peer !== null) {
      this.peer.inbox.push(JSON.parse(JSON.stringify(m)) as LinkMessage);
    }
  }
  onMessage(l: (m: LinkMessage) => void): void {
    this.listener = l;
  }
  close(): void {
    this.peer = null;
  }
}

function pump(a: LinkEnd, b: LinkEnd): void {
  while (a.inbox.length > 0 || b.inbox.length > 0) {
    for (const e of [a, b]) {
      while (e.inbox.length > 0) {
        const m = e.inbox.shift() as LinkMessage;
        if (e.listener !== null) {
          e.listener(m);
        }
      }
    }
  }
}

function arrivals(out: FakeOutput): string[] {
  return out.played.filter((s: Segment) => s.kind === SegmentKind.ARRIVAL).map((s: Segment) => s.poiId);
}

export default function twoDeviceTest() {
  describe('twoDevice', () => {
    it('leadSpeaksFollowVibratesHandoffNoRepeats', 0, () => {
      const pois: Poi[] = [poiAt('Brama', 80, 5, 0.9), poiAt('Kosciol', 300, 5, 0.9), poiAt('Wieza', 520, 5, 0.9)];
      const clock = new FakeClock();
      const phoneOut = new FakeOutput();
      const watchOut = new FakeOutput();
      const phone = new WalkController(pois, [], null, phoneOut, clock);
      const watch = new WalkController(pois, [], null, watchOut, clock);
      const haptics = new FakeHaptics();
      watch.setHaptics(haptics);
      const a = new LinkEnd();
      const b = new LinkEnd();
      a.peer = b;
      b.peer = a;
      phone.connect(a, 'phone', true);
      watch.connect(b, 'watch', false);
      pump(a, b);
      const fixes: GeoFix[] = walkNorth(0, 600, 0);
      for (let i = 0; i < fixes.length; i++) {
        clock.t = fixes[i].t;
        phone.onFix(fixes[i]);
        watch.onFix(fixes[i]);
        pump(a, b);
        if (i === 200) {
          watch.takeOver();
          pump(a, b);
          expect(watch.deviceRole()).assertEqual(DeviceRole.LEAD);
          expect(phone.deviceRole()).assertEqual(DeviceRole.FOLLOW);
        }
      }
      expect(arrivals(phoneOut).length > 0).assertTrue();
      expect(arrivals(watchOut).length > 0).assertTrue();
      const all = arrivals(phoneOut).concat(arrivals(watchOut));
      expect(new Set<string>(all).size).assertEqual(all.length);
      expect(haptics.cues.indexOf(HapticCue.ARRIVED) >= 0).assertTrue();
    });
  });
}
