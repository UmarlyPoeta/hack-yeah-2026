// npm run warm -- [--limit N] [--interests historia,sztuka] [--no-voice] [--dry-run]
//
// Walks fixtures/demo-route-krakow.json and generates WELCOME / ARRIVAL / BRIDGE text and audio for the stops,
// into the same caches the server reads (.cache/segments.json, .cache/audio/). Saves Bielik time during the
// demo and ElevenLabs characters (free plan: 10 000/month), so start with a small --limit and check --dry-run.
// The app hits these entries only with the same interests and the same maxWords bucket (multiples of 10).
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { loadConfig } from '../src/config.js';
import { parseSegmentRequest } from '../src/segment/SegmentGenerator.js';
import { walkPlan } from '../src/segment/walkPlan.js';
import { createServices } from '../src/services.js';

const { values: opts } = parseArgs({
  options: {
    limit: { type: 'string', default: '5' },
    interests: { type: 'string', default: '' },
    'no-voice': { type: 'boolean', default: false },
    'dry-run': { type: 'boolean', default: false },
    route: { type: 'string', default: '../fixtures/demo-route-krakow.json' },
  },
});

const config = loadConfig();
// latency does not matter here, and the first request after a pause waits ~90 s for the Modal container
config.llmTimeoutMs = Math.max(config.llmTimeoutMs, 180_000);
config.llmDeepDiveTimeoutMs = Math.max(config.llmDeepDiveTimeoutMs, 180_000);
const { poiService, segments, tts } = createServices(config, () => {});
const route = JSON.parse(readFileSync(path.resolve(import.meta.dirname, '..', opts.route), 'utf8'));
const interests = opts.interests ? opts.interests.split(',').map((s) => s.trim()) : [];
const plan = walkPlan(route, poiService.fixturePois, { interests, limit: Number(opts.limit) });
const voice = !opts['no-voice'];

console.log(`plan: ${plan.length} segments for ${Number(opts.limit)} stops, interests [${interests.join(', ')}], voice ${voice ? tts?.providers.map((p) => p.name).join(' -> ') ?? 'none' : 'off'}`);
const estChars = plan.reduce((n, r) => n + r.maxWords * 7, 0);
console.log(`ElevenLabs upper estimate: ~${estChars} characters (~7 per word; cached audio costs nothing)`);
if (opts['dry-run']) {
  for (const r of plan) console.log(`  ${r.kind.padEnd(9)} ${(poiService.get(r.poiId)?.name ?? r.poiId).padEnd(50)} maxWords ${r.maxWords}`);
  process.exit(0);
}

const summary = { ai: 0, template: 0, audio: 0, chars: 0 };
for (const r of plan) {
  const t0 = Date.now();
  const s = await segments.generate(parseSegmentRequest({ ...r, voice }));
  summary[s.origin]++;
  if (s.audioUrl) summary.audio++;
  if (s.voice?.startsWith('elevenlabs')) summary.chars += s.text.length;
  const name = poiService.get(r.poiId)?.name ?? r.poiId;
  console.log(
    `${r.kind.padEnd(9)} ${name.slice(0, 40).padEnd(40)} ${s.origin.padEnd(8)} ${String(s.text.split(/\s+/).length).padStart(3)} words ` +
      `${s.durationMs ? `${(s.durationMs / 1000).toFixed(1)}s ${s.voice}` : 'no audio'} ${((Date.now() - t0) / 1000).toFixed(1)}s ${s.warnings.join(',')}`,
  );
}
console.log(`\ndone: ${summary.ai} ai, ${summary.template} template, ${summary.audio} with audio; ElevenLabs characters in this run's segments ≤ ${summary.chars}`);
