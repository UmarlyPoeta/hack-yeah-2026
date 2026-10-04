// TTS (#19): MP3 duration, provider chain ElevenLabs -> Piper -> none, audio cache, /v1/audio, segments with voice,
// warm-up plan. ElevenLabs and Piper are mocked: no network, no binaries.
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, before, describe, it } from 'node:test';
import { JsonCache } from '../src/cache/JsonCache.js';
import { createApp } from '../src/http/app.js';
import { SegmentGenerator } from '../src/segment/SegmentGenerator.js';
import { segmentRoutes } from '../src/segment/routes.js';
import { stopsAlong, walkPlan } from '../src/segment/walkPlan.js';
import { mp3DurationMs } from '../src/tts/mp3.js';
import { ElevenLabsTts, PiperTts, TtsError } from '../src/tts/providers.js';
import { audioRoutes } from '../src/tts/routes.js';
import { AudioStore, TtsService } from '../src/tts/TtsService.js';
import { failingFetch, fakeClock, listen, makeService, recorded } from './helpers.js';

const TONE_44K = readFileSync(new URL('./fixtures/tone-1500ms-44k.mp3', import.meta.url));
const TONE_22K = readFileSync(new URL('./fixtures/tone-1000ms-22k-vbr.mp3', import.meta.url));

const tmpDirs = [];
function store() {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'audio-test-'));
  tmpDirs.push(dir);
  return new AudioStore({ dir, meta: new JsonCache({ ttlMs: 60_000 }) });
}
after(() => tmpDirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

/** Fake provider: answers from a list ('quota' | 'down' | Buffer), counts calls. */
function fakeProvider(name, cloud, answers) {
  let i = 0;
  return {
    name, cloud, voice: `${name}:test`, calls: [],
    available: () => true,
    async synthesize(text) {
      this.calls.push(text);
      const a = answers[Math.min(i++, answers.length - 1)];
      if (a === 'quota') throw new TtsError('quota', 'quota_exceeded');
      if (a === 'down') throw new TtsError('unavailable', 'HTTP 500');
      return a;
    },
  };
}

describe('mp3DurationMs', () => {
  it('measures CBR 44.1 kHz and VBR 22 kHz within 80 ms of the real length', () => {
    assert.ok(Math.abs(mp3DurationMs(TONE_44K) - 1500) <= 80, `${mp3DurationMs(TONE_44K)}`);
    assert.ok(Math.abs(mp3DurationMs(TONE_22K) - 1000) <= 80, `${mp3DurationMs(TONE_22K)}`);
  });

  it('returns 0 for bytes that are not MP3', () => {
    assert.equal(mp3DurationMs(Buffer.from('<html>error</html>')), 0);
  });
});

describe('TtsService', () => {
  it('ElevenLabs first; the same text is served from the cache', async () => {
    const eleven = fakeProvider('elevenlabs', true, [TONE_44K]);
    const tts = new TtsService({ providers: [eleven, fakeProvider('piper', false, [TONE_22K])], store: store() });
    const a = await tts.speak('Dzień dobry.', { allowCloud: true });
    assert.equal(a.voice, 'elevenlabs:test');
    assert.ok(a.durationMs > 1400);
    assert.deepEqual(a.warnings, []);
    const b = await tts.speak('Dzień dobry.', { allowCloud: true });
    assert.equal(b.audioId, a.audioId);
    assert.equal(eleven.calls.length, 1);
  });

  it('ElevenLabs error -> Piper with tts_fallback_piper', async () => {
    const tts = new TtsService({ providers: [fakeProvider('elevenlabs', true, ['down']), fakeProvider('piper', false, [TONE_22K])], store: store() });
    const a = await tts.speak('Tekst.', { allowCloud: true });
    assert.equal(a.voice, 'piper:test');
    assert.deepEqual(a.warnings, ['tts_fallback_piper']);
  });

  it('both fail -> no audio, tts_unavailable', async () => {
    const tts = new TtsService({ providers: [fakeProvider('elevenlabs', true, ['down']), fakeProvider('piper', false, ['down'])], store: store() });
    assert.deepEqual(await tts.speak('Tekst.', { allowCloud: true }), { audioId: null, durationMs: null, voice: null, warnings: ['tts_unavailable'] });
  });

  it('quota error switches ElevenLabs off for 10 minutes', async () => {
    const clock = fakeClock();
    const eleven = fakeProvider('elevenlabs', true, ['quota', TONE_44K]);
    const tts = new TtsService({ providers: [eleven, fakeProvider('piper', false, [TONE_22K])], store: store(), now: clock });
    await tts.speak('Jeden.', { allowCloud: true });
    await tts.speak('Dwa.', { allowCloud: true });
    assert.equal(eleven.calls.length, 1);
    assert.deepEqual(tts.health(), { ok: true, provider: 'piper' });
    clock.t += 11 * 60 * 1000;
    assert.equal((await tts.speak('Trzy.', { allowCloud: true })).voice, 'elevenlabs:test');
  });

  it('allowCloud=false (template segments) goes straight to Piper, without a fallback warning', async () => {
    const eleven = fakeProvider('elevenlabs', true, [TONE_44K]);
    const tts = new TtsService({ providers: [eleven, fakeProvider('piper', false, [TONE_22K])], store: store() });
    const a = await tts.speak('Szablon.', { allowCloud: false });
    assert.equal(a.voice, 'piper:test');
    assert.deepEqual(a.warnings, []);
    assert.equal(eleven.calls.length, 0);
  });

  it('a provider returning non-MP3 bytes counts as a failure', async () => {
    const tts = new TtsService({ providers: [fakeProvider('elevenlabs', true, [Buffer.from('{"error":1}')]), fakeProvider('piper', false, [TONE_22K])], store: store() });
    assert.equal((await tts.speak('Tekst.', { allowCloud: true })).voice, 'piper:test');
  });
});

describe('providers', () => {
  it('ElevenLabs sends text, model and language; 401 is a quota error; the key is never in the message', async () => {
    const calls = [];
    const fetch = async (url, init) => {
      calls.push({ url, init });
      return calls.length === 1 ? new Response(TONE_44K, { status: 200 }) : new Response('{"detail":{"status":"quota_exceeded"}}', { status: 401 });
    };
    const eleven = new ElevenLabsTts({ apiKey: 'sk-secret', voiceId: 'voice1', fetch });
    assert.equal((await eleven.synthesize('Cześć')).length, TONE_44K.length);
    assert.match(calls[0].url, /\/v1\/text-to-speech\/voice1\?output_format=mp3_44100_128$/);
    assert.deepEqual(JSON.parse(calls[0].init.body), { text: 'Cześć', model_id: 'eleven_multilingual_v2', language_code: 'pl' });
    assert.equal(calls[0].init.headers['xi-api-key'], 'sk-secret');
    await assert.rejects(eleven.synthesize('x'), (e) => e.code === 'quota' && !e.message.includes('sk-secret'));
  });

  it('Piper: text on stdin to piper, then ffmpeg WAV -> MP3', async () => {
    const runs = [];
    const run = async (cmd, args, input) => {
      runs.push({ cmd, args, input });
      return cmd === 'ffmpeg' ? TONE_22K : Buffer.alloc(0);
    };
    const piper = new PiperTts({ bin: 'piper', voicePath: '/voices/pl_PL-gosia-medium.onnx', ffmpeg: 'ffmpeg', run });
    assert.equal(piper.voice, 'piper:pl_PL-gosia-medium');
    assert.equal(await piper.synthesize('Zażółć gęślą jaźń.'), TONE_22K);
    assert.equal(runs[0].input, 'Zażółć gęślą jaźń.');
    assert.equal(runs[0].args[runs[0].args.indexOf('--output_file') + 1], runs[1].args[runs[1].args.indexOf('-i') + 1]);
    assert.deepEqual(runs[1].args.slice(-2), ['mp3', 'pipe:1']);
  });
});

describe('segments with voice + GET /v1/audio', () => {
  let app;
  let audioStore;
  before(async () => {
    audioStore = store();
    const tts = new TtsService({ providers: [fakeProvider('elevenlabs', true, [TONE_44K]), fakeProvider('piper', false, [TONE_22K])], store: audioStore });
    const poiService = makeService({ fetch: failingFetch() });
    const generator = new SegmentGenerator({ poiService, llm: null, tts, cache: new JsonCache({ ttlMs: 60_000 }) });
    app = await listen(createApp({ poiService, routes: [...segmentRoutes(generator), ...audioRoutes(audioStore)] }));
  });
  after(() => app.close());

  it('template segment with voice -> Piper audio, audioUrl serves the MP3', async () => {
    const res = await fetch(`${app.base}/v1/segment`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ kind: 'APPROACH', poiId: 'plwiki:1039593', interests: [], maxWords: 20, voice: true }),
    });
    const s = await res.json();
    assert.equal(s.voice, 'piper:test');
    assert.match(s.audioUrl, /^\/v1\/audio\/[a-f0-9]{24}\.mp3$/);
    assert.ok(Math.abs(s.durationMs - 1000) <= 80);
    assert.deepEqual(s.warnings, []);
    const audio = await fetch(app.base + s.audioUrl);
    assert.equal(audio.status, 200);
    assert.equal(audio.headers.get('content-type'), 'audio/mpeg');
    assert.deepEqual(Buffer.from(await audio.arrayBuffer()), TONE_22K);
  });

  it('404 for unknown audio, and ids that are not hex never reach the file system', async () => {
    assert.equal((await fetch(`${app.base}/v1/audio/${'0'.repeat(24)}.mp3`)).status, 404);
    assert.equal((await fetch(`${app.base}/v1/audio/..%2F..%2Fsegments.json.mp3`)).status, 404);
  });
});

describe('walkPlan (npm run warm)', () => {
  const route = recorded('../../../fixtures/demo-route-krakow.json');
  const pois = recorded('../../../fixtures/pois-krakow.json').pois;

  it('stops come in walking order; WELCOME first, then ARRIVAL and BRIDGE with bucketed budgets', () => {
    const stops = stopsAlong(route, pois);
    assert.equal(stops[0].poi.name, 'Barbakan w Krakowie');
    assert.ok(stops.every((s, i) => i === 0 || s.t >= stops[i - 1].t));
    const plan = walkPlan(route, pois, { limit: 3 });
    assert.deepEqual(plan.map((r) => r.kind), ['WELCOME', 'ARRIVAL', 'BRIDGE', 'ARRIVAL', 'ARRIVAL']);
    assert.ok(plan.every((r) => r.maxWords % 10 === 0));
    assert.ok(plan.filter((r) => r.kind === 'ARRIVAL').every((r) => r.maxWords >= 40 && r.maxWords <= 120));
    const bridge = plan.find((r) => r.kind === 'BRIDGE');
    assert.equal(bridge.fromPoiId, stops[0].poi.id);
    assert.equal(bridge.poiId, stops[1].poi.id);
  });
});
