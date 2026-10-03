import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GeoFix } from '../src/model/GeoPoint';
import { Segment, SegmentKind, SegmentOrigin } from '../src/model/Segment';
import { GuideDirector, GuideEvents } from '../src/guide/GuideDirector';
import { GuideAction, GuideActionKind } from '../src/guide/NarrationPlanner';
import { countWords, estimateDurationMs } from '../src/guide/Templates';
import { demoPoisWithSignals, demoRoute, fixAt, plays, poiAt, runWalk, withNoise } from './helpers';

function seg(a: GuideAction): Segment {
  assert.ok(a.segment !== null);
  return a.segment;
}

function demoWalk(route: GeoFix[] = demoRoute()): GuideAction[] {
  return runWalk(new GuideDirector(demoPoisWithSignals(), [], true), route);
}

// A walk north at 1.3 m/s, one fix per second, from `fromM` to `toM` metres.
function walkNorth(fromM: number, toM: number, startS: number): GeoFix[] {
  const out: GeoFix[] = [];
  let t = startS;
  for (let m = fromM; m <= toM; m += 1.3) {
    out.push(fixAt(m, 0, t));
    t++;
  }
  return out;
}

function standAt(north: number, fromS: number, seconds: number): GeoFix[] {
  const out: GeoFix[] = [];
  for (let k = 0; k < seconds; k++) {
    out.push(fixAt(north, 0, fromS + k));
  }
  return out;
}

const NAME = (s: Segment, prefix: string): boolean => s.text.includes(prefix);

test('1. demo walk: WELCOME first, each stop told once, BRIDGE only right after its ARRIVAL', () => {
  const p = plays(demoWalk()).map(seg);
  assert.equal(p[0].kind, SegmentKind.WELCOME);
  assert.equal(p.filter((s) => s.kind === SegmentKind.WELCOME).length, 1);
  const arrivals = p.filter((s) => s.kind === SegmentKind.ARRIVAL);
  assert.equal(new Set<string>(arrivals.map((s) => s.poiId)).size, arrivals.length, 'a stop told twice');
  assert.ok(arrivals.length >= 10 && arrivals.length <= 16, `${arrivals.length} stops on a 19 min walk`);
  let lastArrival: string | null = null;
  for (const s of p) {
    if (s.kind === SegmentKind.ARRIVAL) {
      lastArrival = s.poiId;
    } else if (s.kind === SegmentKind.BRIDGE) {
      assert.equal(s.fromPoiId, lastArrival, 'BRIDGE must start from the last told stop');
    }
  }
});

test('2. demo walk: the main sights come in walking order', () => {
  const arrivals = plays(demoWalk()).map(seg).filter((s) => s.kind === SegmentKind.ARRIVAL);
  const order = ['Barbakan', 'Brama Floriańska', 'Kościół archiprezbiterialny', 'Sukiennice', 'Dzwon Zygmunt']
    .map((n: string) => arrivals.findIndex((s) => s.text.startsWith(n)));
  assert.ok(order.every((i) => i >= 0), `missing: ${order}`);
  for (let i = 1; i < order.length; i++) {
    assert.ok(order[i] > order[i - 1], `out of order: ${order}`);
  }
});

test('3. two sights 15 m apart are one stop: one ARRIVAL mentioning the other, no BRIDGE between', () => {
  const pois = [poiAt('Brama', 60, 5, 0.8), poiAt('Baszta', 75, 5, 0.5), poiAt('Kościół', 300, 5, 0.8)];
  const p = plays(runWalk(new GuideDirector(pois, [], true), walkNorth(0, 120, 0))).map(seg);
  const arrivals = p.filter((s) => s.kind === SegmentKind.ARRIVAL);
  assert.equal(arrivals.length, 1);
  assert.ok(arrivals[0].text.includes('Obok: Baszta'), arrivals[0].text);
});

test('3b. two main stops close together: no BRIDGE, the second is announced', () => {
  // 50 m apart: the first story (sized to the gap) ends when the second is only seconds away
  const pois = [poiAt('Pierwszy', 100, 5, 0.8), poiAt('Drugi', 150, 5, 0.8)];
  for (const p of pois) {
    p.summary = 'Zdanie numer jeden ma pięć słów. '.repeat(40);
  }
  const p = plays(runWalk(new GuideDirector(pois, [], true), walkNorth(0, 200, 0))).map(seg);
  assert.equal(p.filter((s) => s.kind === SegmentKind.ARRIVAL).length, 2);
  assert.equal(p.filter((s) => s.kind === SegmentKind.BRIDGE).length, 0);
});

test('4. standing 20 s on the 35/50 m border gives exactly one ARRIVAL', () => {
  const pois = [poiAt('Pomnik', 100, 0, 0.8)];
  const fixes = walkNorth(0, 66, 0).concat(standAt(66, 60, 10), standAt(64, 70, 5), standAt(52, 75, 5));
  const p = plays(runWalk(new GuideDirector(pois, [], true), fixes)).map(seg);
  assert.equal(p.filter((s) => s.kind === SegmentKind.ARRIVAL).length, 1);
});

test('5. stopping after the story offers a deep dive; accepting plays it; walking on withdraws an offer', () => {
  const pois = [poiAt('Sukiennice', 60, 10, 0.9)];
  const d = new GuideDirector(pois, [], true);
  const before = runWalk(d, walkNorth(0, 62, 0), 0);
  assert.ok(plays(before).some((a) => seg(a).kind === SegmentKind.ARRIVAL));
  const standing = runWalk(d, standAt(62, 48, 50), 0);
  const offer = standing.find((a) => a.kind === GuideActionKind.OFFER_DEEP_DIVE);
  assert.ok(offer !== undefined, 'no offer while standing');
  // accept: the AI text is not there, so after the wait the template deep dive plays
  const t0 = 98000;   // after the standing walk above
  const acc = d.step(GuideEvents.deepDiveAccepted('Sukiennice', t0));
  assert.ok(acc.some((a) => a.kind === GuideActionKind.REQUEST_SEGMENT && a.request?.kind === SegmentKind.DEEP_DIVE));
  let deep: GuideAction | undefined;
  for (let t = t0 + 1000; t < t0 + 12000 && deep === undefined; t += 1000) {
    deep = d.step(GuideEvents.tick(t)).find((a) => a.kind === GuideActionKind.PLAY_SEGMENT);
  }
  assert.ok(deep !== undefined && seg(deep).kind === SegmentKind.DEEP_DIVE);
  assert.ok(deep.t - t0 >= 8000, 'waited for the AI text first');

  // a second stop: offer, then walk away -> withdrawn
  const d2 = new GuideDirector([poiAt('Wieża', 60, 10, 0.9)], [], true);
  runWalk(d2, walkNorth(0, 62, 0), 0);
  const offered = runWalk(d2, standAt(62, 48, 50), 0).some((a) => a.kind === GuideActionKind.OFFER_DEEP_DIVE);
  const away = runWalk(d2, walkNorth(63, 120, 98), 0);
  assert.ok(offered && away.some((a) => a.kind === GuideActionKind.WITHDRAW_DEEP_DIVE));
});

test('5b. no offer when the user keeps walking', () => {
  const p = runWalk(new GuideDirector([poiAt('Pomnik', 60, 10, 0.9)], [], true), walkNorth(0, 200, 0));
  assert.ok(!p.some((a) => a.kind === GuideActionKind.OFFER_DEEP_DIVE));
});

test('6. ARRIVAL length fits the time to the next stop', () => {
  const longText = 'Zdanie numer jeden ma pięć słów. '.repeat(40);
  // (far enough from the start for a heading, so the stop after A is already known on arrival)
  const near = [poiAt('A', 100, 5, 0.9), poiAt('B', 145, 5, 0.9)];        // 45 m apart: short story
  const far = [poiAt('A', 100, 5, 0.9), poiAt('B', 400, 5, 0.9)];         // ~230 s apart: long story
  for (const pois of [near, far]) {
    for (const p of pois) {
      p.summary = longText;
    }
  }
  const first = (pois: typeof near): Segment => plays(runWalk(new GuideDirector(pois, [], true), walkNorth(0, 110, 0)))
    .map(seg).filter((s) => s.kind === SegmentKind.ARRIVAL)[0];
  // near: B's story starts 45 m after A's, i.e. ~35 s later; A's story must be over by then
  const nearMs = estimateDurationMs(first(near).text);
  assert.ok(nearMs <= 35000 * 0.75, `near: ${countWords(first(near).text)} words, ${nearMs} ms`);
  const farWords = countWords(first(far).text);
  assert.ok(farWords > 80 && farWords <= 120, `far: ${farWords} words`);
});

test('7. demo walk: segments never overlap', () => {
  const p = plays(demoWalk());
  for (let i = 1; i < p.length; i++) {
    const prevEnd = p[i - 1].t + estimateDurationMs(seg(p[i - 1]).text);
    assert.ok(p[i].t >= prevEnd, `${seg(p[i]).kind} at ${p[i].t} starts before ${prevEnd}`);
  }
});

test('7b. PLAYBACK_FINISHED frees the narrator early', () => {
  const d = new GuideDirector([poiAt('A', 30, 0, 0.9), poiAt('B', 40, 60, 0.9)], [], true);
  const first = d.step(GuideEvents.fix(fixAt(0, 0, 0))).find((a) => a.kind === GuideActionKind.PLAY_SEGMENT);
  assert.ok(first !== undefined);
  // the WELCOME would take several seconds; finishing it at once lets the next segment start
  const next = d.step(GuideEvents.playbackFinished(seg(first).id, 500)).concat(runWalk(d, walkNorth(1.3, 40, 1), 0))
    .filter((a) => a.kind === GuideActionKind.PLAY_SEGMENT);
  assert.ok(next.length > 0 && next[0].t < first.t + estimateDurationMs(seg(first).text));
});

test('8. an APPROACH for a place already reached is never played', () => {
  // announced at ~30 s ETA, then a long WELCOME-like wait is impossible here, so check the rule directly:
  const p = plays(demoWalk()).map(seg);
  for (let i = 0; i < p.length; i++) {
    if (p[i].kind === SegmentKind.APPROACH) {
      const laterArrival = p.slice(0, i).some((s) => s.kind === SegmentKind.ARRIVAL && s.poiId === p[i].poiId);
      assert.ok(!laterArrival, `APPROACH after its ARRIVAL: ${p[i].text}`);
    }
  }
});

test('9. bad fixes (150 m accuracy, 300 m jump) trigger nothing', () => {
  const d = new GuideDirector([poiAt('Daleko', 300, 0, 0.9)], [], true);
  runWalk(d, walkNorth(0, 20, 0), 0);
  const bad = d.step(GuideEvents.fix(fixAt(300, 0, 17, 150))).concat(d.step(GuideEvents.fix(fixAt(300, 0, 18))));
  assert.ok(!plays(bad).some((a) => seg(a).kind === SegmentKind.ARRIVAL));
});

test('9b. GPS noise: still told in order, never twice', () => {
  for (let seed = 1; seed <= 3; seed++) {
    const arrivals = plays(demoWalk(withNoise(demoRoute(), 5, seed))).map(seg).filter((s) => s.kind === SegmentKind.ARRIVAL);
    assert.equal(new Set<string>(arrivals.map((s) => s.poiId)).size, arrivals.length);
    const iB = arrivals.findIndex((s) => NAME(s, 'Brama Floriańska ('));
    const iS = arrivals.findIndex((s) => NAME(s, 'Sukiennice –'));
    assert.ok(iB >= 0 && iS > iB, `seed ${seed}: Brama ${iB}, Sukiennice ${iS}`);
  }
});

test('10. no places at all: only WELCOME, no errors', () => {
  const p = plays(runWalk(new GuideDirector([], [], true), walkNorth(0, 100, 0))).map(seg);
  assert.deepEqual(p.map((s) => s.kind), [SegmentKind.WELCOME]);
});

test('AI segment that arrives in time replaces the template; requests carry deadlines', () => {
  const pois = [poiAt('Brama', 80, 5, 0.9)];
  const d = new GuideDirector(pois, [], true);
  const start = d.step(GuideEvents.fix(fixAt(0, 0, 0)));
  const req = start.concat(runWalk(d, walkNorth(1.3, 30, 1), 0))
    .find((a) => a.kind === GuideActionKind.REQUEST_SEGMENT && a.request?.kind === SegmentKind.ARRIVAL);
  assert.ok(req !== undefined && req.request !== null && req.deadlineT > req.t);
  const ai: Segment = {
    id: 'ai-1', kind: SegmentKind.ARRIVAL, poiId: 'Brama', fromPoiId: null, text: 'Tekst od Bielika o bramie.',
    claims: [], origin: SegmentOrigin.AI, llmModel: 'bielik', audioUrl: '/v1/audio/ai-1.mp3', durationMs: 4000,
    voice: 'elevenlabs:x', sourceUrls: ['u'], warnings: []
  };
  d.step(GuideEvents.segmentReady(ai, 24000));
  const arrival = plays(runWalk(d, walkNorth(32.5, 90, 25), 0)).map(seg).find((s) => s.kind === SegmentKind.ARRIVAL);
  assert.equal(arrival?.id, 'ai-1');
});
