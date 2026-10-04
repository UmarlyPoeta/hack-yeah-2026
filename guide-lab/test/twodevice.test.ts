import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GeoFix } from '../src/model/GeoPoint';
import { Segment, SegmentKind } from '../src/model/Segment';
import { GuideDirector } from '../src/guide/GuideDirector';
import { DeviceLink, LinkMessage, LinkMessageKind } from '../src/link/DeviceLink';
import { HapticCue, HapticOutput } from '../src/viewmodel/Haptics';
import { Clock, DeviceRole, NarrationOutput, PEER_TIMEOUT_MS, WalkController } from '../src/viewmodel/WalkController';
import { demoPoisWithSignals, demoRoute, plays, runWalk } from './helpers';

class FakeClock implements Clock {
  t: number = 0;
  now(): number {
    return this.t;
  }
}

class FakeOutput implements NarrationOutput {
  played: Segment[] = [];
  stops: number = 0;
  play(segment: Segment): void {
    this.played.push(segment);
  }
  stop(): void {
    this.stops++;
  }
}

class FakeHaptics implements HapticOutput {
  cues: HapticCue[] = [];
  cue(c: HapticCue): void {
    this.cues.push(c);
  }
}

// Two connected ends; messages wait in a queue until pump(), like a real network hop.
class LinkEnd implements DeviceLink {
  peer: LinkEnd | null = null;
  inbox: LinkMessage[] = [];
  sent: LinkMessage[] = [];
  listener: ((m: LinkMessage) => void) | null = null;
  up: boolean = true;
  send(m: LinkMessage): void {
    this.sent.push(m);
    if (this.up && this.peer !== null) {
      this.peer.inbox.push(JSON.parse(JSON.stringify(m)) as LinkMessage);   // a real link serialises
    }
  }
  onMessage(l: (m: LinkMessage) => void): void {
    this.listener = l;
  }
  close(): void {
    this.up = false;
  }
}

function linkPair(): [LinkEnd, LinkEnd] {
  const a = new LinkEnd();
  const b = new LinkEnd();
  a.peer = b;
  b.peer = a;
  return [a, b];
}

function pump(ends: LinkEnd[]): void {
  let moved = true;
  while (moved) {
    moved = false;
    for (const e of ends) {
      while (e.inbox.length > 0) {
        const m = e.inbox.shift() as LinkMessage;
        if (e.listener !== null) {
          e.listener(m);
        }
        moved = true;
      }
    }
  }
}

interface Rig {
  clock: FakeClock;
  phone: WalkController;
  watch: WalkController;
  phoneOut: FakeOutput;
  watchOut: FakeOutput;
  watchHaptics: FakeHaptics;
  ends: LinkEnd[];
}

function rig(): Rig {
  const clock = new FakeClock();
  const pois = demoPoisWithSignals();
  const phoneOut = new FakeOutput();
  const watchOut = new FakeOutput();
  const phone = new WalkController(pois, [], null, phoneOut, clock);
  const watch = new WalkController(pois, [], null, watchOut, clock);
  const watchHaptics = new FakeHaptics();
  watch.setHaptics(watchHaptics);
  const [a, b] = linkPair();
  phone.connect(a, 'phone', true);
  watch.connect(b, 'watch', false);
  pump([a, b]);
  return { clock: clock, phone: phone, watch: watch, phoneOut: phoneOut, watchOut: watchOut, watchHaptics: watchHaptics, ends: [a, b] };
}

// Both devices walk the same route (the user wears both); one TICK per second between fixes.
function walkBoth(r: Rig, fixes: GeoFix[], onSecond: (t: number) => void = () => {}): void {
  for (let i = 0; i < fixes.length; i++) {
    r.clock.t = fixes[i].t;
    r.phone.onFix(fixes[i]);
    r.watch.onFix(fixes[i]);
    pump(r.ends);
    const end = i + 1 < fixes.length ? fixes[i + 1].t : fixes[i].t + 30000;
    for (let t = fixes[i].t + 1000; t < end; t += 1000) {
      r.clock.t = t;
      r.phone.tick();
      r.watch.tick();
      pump(r.ends);
      onSecond(t);
    }
  }
}

function arrivalIds(segments: Segment[]): string[] {
  return segments.filter((s) => s.kind === SegmentKind.ARRIVAL).map((s) => s.poiId);
}

test('LEAD speaks, FOLLOW stays silent but shows the same story and vibrates', () => {
  const r = rig();
  assert.equal(r.phone.state().role, DeviceRole.LEAD);
  assert.equal(r.watch.state().role, DeviceRole.FOLLOW);
  walkBoth(r, demoRoute().slice(0, 70));
  assert.ok(arrivalIds(r.phoneOut.played).length >= 3, 'phone told stories');
  assert.equal(r.watchOut.played.length, 0, 'watch never speaks as FOLLOW');
  assert.equal(r.watch.state().currentText, r.phone.state().currentText);
  assert.ok(r.watch.state().peerConnected);
  assert.ok(r.watchHaptics.cues.includes(HapticCue.ARRIVED), 'arrival felt on the wrist');
  assert.ok(r.watchHaptics.cues.some((c) => c === HapticCue.LOOK_LEFT || c === HapticCue.LOOK_RIGHT
    || c === HapticCue.LOOK_AHEAD), 'approach felt on the wrist');
  assert.ok(r.watch.state().nextPoiName.length > 0, 'watch has its own next stop from its own GPS');
});

test('privacy: the link never carries position, distance or bearing', () => {
  const r = rig();
  walkBoth(r, demoRoute().slice(0, 40));
  const json = JSON.stringify(r.ends[0].sent.concat(r.ends[1].sent));
  for (const forbidden of ['"lat"', '"lon"', 'distanceM', 'bearingAngle', 'etaSeconds']) {
    assert.ok(!json.includes(forbidden), forbidden + ' leaked into the link');
  }
});

test('commands from the watch run on the phone: pause, resume, skip', () => {
  const r = rig();
  walkBoth(r, demoRoute().slice(0, 10));
  r.watch.pauseNarration();
  pump(r.ends);
  assert.ok(r.phone.state().narrationPaused);
  const before = r.phoneOut.played.length;
  walkBoth(r, demoRoute().slice(10, 40));
  assert.equal(r.phoneOut.played.length, before, 'nothing new while paused');
  assert.ok(r.watch.state().narrationPaused, 'the watch shows the pause too');
  r.watch.resumeNarration();
  pump(r.ends);
  walkBoth(r, demoRoute().slice(40, 70));
  assert.ok(r.phoneOut.played.length > before, 'talks again after resume');
  const stopsBefore = r.phoneOut.stops;
  r.watch.skip();
  pump(r.ends);
  assert.ok(r.phoneOut.stops > stopsBefore, 'skip stops the current audio');
});

test('handoff in the middle of the walk: the watch goes on, nothing is told twice', () => {
  const r = rig();
  const route = demoRoute();
  walkBoth(r, route.slice(0, 80));
  const toldByPhone = arrivalIds(r.phoneOut.played);
  assert.ok(toldByPhone.length >= 3);
  r.watch.takeOver();
  pump(r.ends);
  assert.equal(r.watch.state().role, DeviceRole.LEAD);
  assert.equal(r.phone.state().role, DeviceRole.FOLLOW);
  const phoneAfter = r.phoneOut.played.length;
  walkBoth(r, route.slice(80));
  assert.equal(r.phoneOut.played.length, phoneAfter, 'phone silent after handing over');
  const toldByWatch = arrivalIds(r.watchOut.played);
  assert.ok(toldByWatch.length >= 3, 'watch tells the rest');
  const all = toldByPhone.concat(toldByWatch);
  assert.equal(new Set<string>(all).size, all.length, 'a stop told twice across devices');
  assert.ok(!r.watchOut.played.some((s) => s.kind === SegmentKind.WELCOME), 'no second welcome');
  assert.equal(r.phone.state().currentText, r.watch.state().currentText, 'phone now mirrors the watch');
});

test('the LEAD disappears: the FOLLOW goes on alone after the timeout', () => {
  const r = rig();
  walkBoth(r, demoRoute().slice(0, 30));
  r.ends[0].close();                      // phone's link dies
  const route = demoRoute().slice(30, 120);
  let soloAt = -1;
  walkBoth(r, route, (t: number) => {
    if (soloAt < 0 && r.watch.state().role === DeviceRole.SOLO) {
      soloAt = t;
    }
  });
  assert.ok(soloAt > 0, 'watch never went SOLO');
  assert.ok(soloAt - route[0].t >= PEER_TIMEOUT_MS - 1000);
  assert.ok(r.watchOut.played.length > 0, 'and speaks on its own');
});

test('after a network gap the FOLLOW goes SOLO, and follows again when the LEAD is back', () => {
  const r = rig();
  walkBoth(r, demoRoute().slice(0, 20));
  r.ends[0].up = false;                       // phone's messages stop arriving
  let soloSeen = false;
  walkBoth(r, demoRoute().slice(20, 40), () => {
    soloSeen = soloSeen || r.watch.state().role === DeviceRole.SOLO;
  });
  assert.ok(soloSeen, 'watch went SOLO during the gap');
  r.ends[0].up = true;                        // network back
  const spokenBefore = r.watchOut.played.length;
  walkBoth(r, demoRoute().slice(40, 60));
  assert.equal(r.watch.state().role, DeviceRole.FOLLOW, 'follows again');
  assert.equal(r.phone.state().role, DeviceRole.LEAD);
  assert.ok(r.watchOut.played.length - spokenBefore <= 1, 'watch stops talking once the LEAD is back');
});

test('engine: progress export/import, mute and replay', () => {
  const pois = demoPoisWithSignals();
  const route = demoRoute();
  const a = new GuideDirector(pois, [], true);
  const told = plays(runWalk(a, route.slice(0, 90), 0)).map((x) => x.segment as Segment);
  const p = a.exportProgress();
  assert.ok(p.spoken.length >= 3);
  const b = new GuideDirector(pois, [], true);
  b.importProgress(p);
  const later = plays(runWalk(b, route.slice(90), 0)).map((x) => x.segment as Segment);
  const both = arrivalIds(told).concat(arrivalIds(later));
  assert.equal(new Set<string>(both).size, both.length);
  const c = new GuideDirector(pois, [], true);
  c.setMuted(true, 0);
  assert.equal(plays(runWalk(c, route.slice(0, 60), 0)).length, 0, 'muted plays nothing');
  const unmuted = c.setMuted(false, route[60].t);
  assert.ok(unmuted.some((x) => x.segment !== null), 'unmuting plays what is waiting');
  const d = new GuideDirector(pois, [], true);
  const first = plays(runWalk(d, route.slice(0, 5), 0));
  const re = d.replay(40000);
  assert.equal(re.length, 1);
  assert.equal(re[0].segment?.id, first[first.length - 1].segment?.id, 'replay plays the last segment again');
});

test('HELLO from a late follower gets the full state at once', () => {
  const r = rig();
  walkBoth(r, demoRoute().slice(0, 20));
  const sent = r.ends[0].sent.filter((m) => m.kind === LinkMessageKind.STATE);
  assert.ok(sent.length > 0 && sent.length < 200, `${sent.length} state messages (heartbeat, not every tick)`);
});
