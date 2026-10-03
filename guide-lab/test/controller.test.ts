import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GeoFix } from '../src/model/GeoPoint';
import { Segment, SegmentKind, SegmentOrigin } from '../src/model/Segment';
import { SegmentRequest } from '../src/guide/NarrationPlanner';
import { Clock, NarrationOutput, SegmentClient, WalkController, WalkUiState } from '../src/viewmodel/WalkController';
import { demoPoisWithSignals, demoRoute, fixAt, poiAt } from './helpers';

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

// A flaky server: every second request fails, the others return an "AI" text.
class FakeClient implements SegmentClient {
  requests: SegmentRequest[] = [];
  request(req: SegmentRequest, deadlineT: number): Promise<Segment | null> {
    this.requests.push(req);
    if (this.requests.length % 2 === 0) {
      return Promise.reject(new Error('timeout'));
    }
    const s: Segment = {
      id: 'ai:' + req.poiId, kind: req.kind, poiId: req.poiId, fromPoiId: req.fromPoiId,
      text: 'Bielik opowiada o ' + req.poiId + '.', claims: [], origin: SegmentOrigin.AI,
      llmModel: 'bielik-4.5b', audioUrl: null, durationMs: 3000, voice: null, sourceUrls: ['u'], warnings: []
    };
    return deadlineT > 0 ? Promise.resolve(s) : Promise.resolve(null);
  }
}

const flush = (): Promise<void> => new Promise<void>((r) => setImmediate(r));

async function drive(c: WalkController, clock: FakeClock, fixes: GeoFix[]): Promise<void> {
  for (let i = 0; i < fixes.length; i++) {
    clock.t = fixes[i].t;
    c.onFix(fixes[i]);
    await flush();
    const end = i + 1 < fixes.length ? fixes[i + 1].t : fixes[i].t + 30000;
    for (let t = fixes[i].t + 1000; t < end; t += 1000) {
      clock.t = t;
      c.tick();
      await flush();
    }
  }
}

test('offline demo walk: templates only, screen state follows the walk', async () => {
  const clock = new FakeClock();
  const out = new FakeOutput();
  const c = new WalkController(demoPoisWithSignals(), [], null, out, clock);
  const seen: string[] = [];
  c.onChange((s: WalkUiState) => {
    if (s.nextPoiName.length > 0 && seen[seen.length - 1] !== s.nextPoiName) {
      seen.push(s.nextPoiName);
    }
  });
  await drive(c, clock, demoRoute().slice(0, 60));
  assert.ok(out.played.length > 3);
  assert.ok(out.played.every((s) => s.origin === SegmentOrigin.TEMPLATE));
  assert.equal(c.state().originLabel, 'szablon');
  assert.ok(seen.includes('Brama Floriańska'), `next stops seen: ${seen}`);
  assert.ok(c.state().laterStops.length <= 4);
});

test('AI segments are used when the server answers; failures fall back silently', async () => {
  const clock = new FakeClock();
  const out = new FakeOutput();
  const client = new FakeClient();
  const c = new WalkController(demoPoisWithSignals(), [], client, out, clock);
  await drive(c, clock, demoRoute().slice(0, 80));
  assert.ok(client.requests.length >= 4, `${client.requests.length} requests`);
  const arrivals = out.played.filter((s) => s.kind === SegmentKind.ARRIVAL);
  assert.ok(arrivals.some((s) => s.origin === SegmentOrigin.AI), 'no AI arrival');
  assert.ok(arrivals.some((s) => s.origin === SegmentOrigin.TEMPLATE), 'a failed request did not fall back');
});

test('deep dive offer appears in the state and accepting it plays the deep dive', async () => {
  const clock = new FakeClock();
  const out = new FakeOutput();
  const c = new WalkController([poiAt('Sukiennice', 60, 10, 0.9)], [], null, out, clock);
  const fixes: GeoFix[] = [];
  let t = 0;
  for (let m = 0; m <= 62; m += 1.3) {
    fixes.push(fixAt(m, 0, t++));
  }
  for (let k = 0; k < 40; k++) {
    fixes.push(fixAt(62, 0, t++));
  }
  await drive(c, clock, fixes);
  assert.equal(c.state().deepDiveOfferId, 'Sukiennice');
  assert.equal(c.state().deepDiveOfferName, 'Sukiennice');
  c.acceptDeepDive();
  for (let k = 0; k < 10; k++) {
    clock.t += 1000;
    c.tick();
  }
  assert.equal(out.played[out.played.length - 1].kind, SegmentKind.DEEP_DIVE);
  assert.equal(c.state().deepDiveOfferId, '');
});

test('pause stops the narrator', () => {
  const out = new FakeOutput();
  const c = new WalkController([], [], null, out, new FakeClock());
  c.pause();
  assert.equal(out.stopped, 1);
});
