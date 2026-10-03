import { describe, expect, it } from '@ohos/hypium';
import { Segment } from '../../main/ets/model/Segment';
import { SegmentFallback, SegmentRequest, SegmentService } from '../../main/ets/data/SegmentService';
import { FakeCall, FakeReply, FakeTransport, networkError, reply, sleep } from './Fakes';

const BASE = 'http://10.0.0.5:8787';

function req(poiId: string, kind: 'ARRIVAL' | 'BRIDGE' | 'DEEP_DIVE' = 'ARRIVAL'): SegmentRequest {
  const r: SegmentRequest = {
    kind: kind, poiId: poiId, fromPoiId: null, interests: ['historia'], maxWords: 90, voice: true,
  };
  return r;
}

function segment(r: SegmentRequest, origin: 'ai' | 'template', text: string): Segment {
  const s: Segment = {
    id: `seg-${r.poiId}`, kind: r.kind, poiId: r.poiId, fromPoiId: r.fromPoiId, text: text, claims: [],
    origin: origin, llmModel: origin === 'ai' ? 'bielik' : null,
    audioUrl: origin === 'ai' ? `/v1/audio/seg-${r.poiId}.mp3` : null,
    durationMs: null, voice: null, sourceUrls: [], warnings: [],
  };
  return s;
}

class TemplateStub implements SegmentFallback {
  built: number = 0;

  build(r: SegmentRequest): Segment {
    this.built++;
    return segment(r, 'template', 'szablon');
  }
}

function aiReply(delayMs: number): (call: FakeCall) => FakeReply {
  return (call: FakeCall) => {
    const r = JSON.parse(call.body) as SegmentRequest;
    return reply(200, JSON.stringify(segment(r, 'ai', 'tekst AI')), delayMs);
  };
}

function service(t: FakeTransport, maxParallel: number = 2): SegmentService {
  return new SegmentService(t, BASE, new TemplateStub(), {
    maxParallel: maxParallel, timeoutMs: 1000, deepDiveTimeoutMs: 2000, now: () => Date.now(),
  });
}

export default function segmentServiceTest() {
  describe('SegmentService', () => {
    it('answer_before_deadline_returns_server_segment', 0, async () => {
      const t = new FakeTransport(aiReply(10));
      const s = await service(t).request(req('plwiki:1'), 500);
      expect(s.origin).assertEqual('ai');
      expect(s.audioUrl).assertEqual(`${BASE}/v1/audio/seg-plwiki:1.mp3`);
      expect(t.calls[0].method).assertEqual('POST');
      expect(t.calls[0].url).assertEqual(`${BASE}/v1/segment`);
      const sent = JSON.parse(t.calls[0].body) as SegmentRequest;
      expect(sent.poiId).assertEqual('plwiki:1');
      expect(sent.maxWords).assertEqual(90);
    });

    it('after_deadline_returns_template_then_announces_upgrade', 0, async () => {
      const t = new FakeTransport(aiReply(150));
      const svc = service(t);
      let upgraded: Segment | null = null;
      svc.onUpgrade((key: string, seg: Segment) => {
        upgraded = seg;
      });
      const started = Date.now();
      const first = await svc.request(req('plwiki:2'), 30);
      expect(first.origin).assertEqual('template');
      expect(Date.now() - started < 140).assertTrue();
      await sleep(200);
      expect((upgraded as Segment | null)?.origin).assertEqual('ai');
      // the late answer is cached: next request gets it at once, without a new call
      const second = await svc.request(req('plwiki:2'), 30);
      expect(second.origin).assertEqual('ai');
      expect(t.calls.length).assertEqual(1);
    });

    it('network_error_returns_template_before_deadline', 0, async () => {
      const t = new FakeTransport(() => networkError(5));
      const started = Date.now();
      const s = await service(t).request(req('plwiki:3'), 1000);
      expect(s.origin).assertEqual('template');
      expect(Date.now() - started < 500).assertTrue();
    });

    it('bad_status_or_body_returns_template', 0, async () => {
      const s1 = await service(new FakeTransport(() => reply(404, '{"error":{}}'))).request(req('plwiki:4'), 500);
      expect(s1.origin).assertEqual('template');
      const s2 = await service(new FakeTransport(() => reply(200, 'nope'))).request(req('plwiki:4'), 500);
      expect(s2.origin).assertEqual('template');
      const wrongKind = (call: FakeCall) => reply(200, JSON.stringify(segment(req('plwiki:4', 'BRIDGE'), 'ai', 'x')));
      const s3 = await service(new FakeTransport(wrongKind)).request(req('plwiki:4'), 500);
      expect(s3.origin).assertEqual('template');
    });

    it('offline_mode_never_calls_http', 0, async () => {
      const t = new FakeTransport(aiReply(0));
      const svc = new SegmentService(t, '', new TemplateStub(), {
        maxParallel: 2, timeoutMs: 1000, deepDiveTimeoutMs: 2000, now: () => Date.now(),
      });
      svc.prefetch(req('plwiki:5'), 1000);
      const s = await svc.request(req('plwiki:5'), 1000);
      expect(s.origin).assertEqual('template');
      expect(t.calls.length).assertEqual(0);
    });

    it('prefetch_is_reused_by_request', 0, async () => {
      const t = new FakeTransport(aiReply(20));
      const svc = service(t);
      svc.prefetch(req('plwiki:6'), 1000);
      await sleep(50);
      const s = await svc.request(req('plwiki:6'), 1000);
      expect(s.origin).assertEqual('ai');
      expect(t.calls.length).assertEqual(1);
    });

    it('limits_parallel_requests', 0, async () => {
      const t = new FakeTransport(aiReply(60));
      const svc = service(t, 1);
      svc.prefetch(req('plwiki:7'), 1000);
      svc.prefetch(req('plwiki:8'), 1000);
      await sleep(20);
      expect(t.calls.length).assertEqual(1);
      expect(svc.inFlight).assertEqual(1);
      await sleep(200);
      expect(t.calls.length).assertEqual(2);
    });

    it('drops_queued_requests_whose_deadline_passed', 0, async () => {
      const t = new FakeTransport(aiReply(100));
      const svc = service(t, 1);
      svc.prefetch(req('plwiki:9'), 1000);
      const late = await svc.request(req('plwiki:10'), 20);
      expect(late.origin).assertEqual('template');
      await sleep(200);
      expect(t.calls.length).assertEqual(1);
    });
  });
}
