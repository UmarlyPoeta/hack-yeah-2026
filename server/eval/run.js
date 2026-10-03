// AI evaluation (#25): 10 stops of the demo route × ARRIVAL, BRIDGE, DEEP_DIVE through the real pipeline
// (Bielik on Modal -> grounding validator -> retry -> template), with an empty cache so every segment is generated.
//
//   npm run eval -- [--stops 10] [--out eval/results]
//
// Writes results/eval-<time>.json (all metrics) and results/review-<time>.md (texts + sources, with empty
// columns for the manual 1–5 rating). No TTS: only the text model is evaluated. Costs ~10 min of the Modal GPU.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { JsonCache } from '../src/cache/JsonCache.js';
import { loadConfig } from '../src/config.js';
import { parseSegmentRequest, SegmentGenerator } from '../src/segment/SegmentGenerator.js';
import { PROMPT_VERSION, SYSTEM_PROMPT } from '../src/segment/prompts.js';
import { stopsAlong } from '../src/segment/walkPlan.js';
import { createServices } from '../src/services.js';
import { countWords } from '../src/validate/grounding.js';

const { values: opts } = parseArgs({
  options: {
    stops: { type: 'string', default: '10' },
    out: { type: 'string', default: 'eval/results' },
  },
});
const SERVER_DIR = path.resolve(import.meta.dirname, '..');
const BUDGET = { ARRIVAL: 90, BRIDGE: 50, DEEP_DIVE: 250 };

const config = loadConfig();
const { poiService, llm } = createServices(config, () => {});
if (!llm) {
  console.error('LLM_MODEL is empty: nothing to evaluate (set it in server/.env).');
  process.exit(1);
}
const logs = [];
const generator = new SegmentGenerator({
  poiService,
  llm,
  cache: new JsonCache({ ttlMs: 1 }),   // in memory, never reused: every request reaches the model
  timeouts: { default: 180_000, deepDive: 180_000 },
  log: (m) => logs.push(m),
});

const route = JSON.parse(readFileSync(path.join(SERVER_DIR, '../fixtures/demo-route-krakow.json'), 'utf8'));
// the app narrates mostly the important places (#40: importance from language versions), so the eval
// takes the N most important sights on the route, kept in walking order
const stops = stopsAlong(route, poiService.fixturePois)
  .filter((s) => (s.poi.role ?? 'sight') === 'sight')
  .sort((a, b) => (b.poi.importance ?? 0) - (a.poi.importance ?? 0))
  .slice(0, Number(opts.stops))
  .sort((a, b) => a.t - b.t);

// wake the Modal container first, so the cold start is measured once and not mixed into the latencies
const t0 = Date.now();
await llm.chat({ system: 'Odpowiedz JSON-em.', user: 'Powiedz "ok".', schema: { type: 'object' }, numPredict: 10, timeoutMs: 240_000 })
  .catch((e) => console.log(`warm-up failed: ${e.message}`));
const coldStartMs = Date.now() - t0;
console.log(`cold start / warm-up: ${(coldStartMs / 1000).toFixed(1)} s; ${stops.length} stops`);

const samples = [];
for (const [i, stop] of stops.entries()) {
  const next = stops[i + 1] ?? stops[i - 1];
  const jobs = [
    { kind: 'ARRIVAL', poiId: stop.poi.id, fromPoiId: null },
    { kind: 'BRIDGE', poiId: next.poi.id, fromPoiId: stop.poi.id },
    { kind: 'DEEP_DIVE', poiId: stop.poi.id, fromPoiId: null },
  ];
  for (const job of jobs) {
    const req = parseSegmentRequest({ ...job, interests: [], maxWords: BUDGET[job.kind], voice: false });
    const before = logs.length;
    const started = Date.now();
    const s = await generator.generate(req);
    const ms = Date.now() - started;
    const sample = {
      kind: s.kind,
      poi: poiService.get(s.poiId).name,
      fromPoi: s.fromPoiId ? poiService.get(s.fromPoiId).name : null,
      origin: s.origin,
      firstPass: s.origin === 'ai' && !s.warnings.includes('validation_retry'),
      warnings: s.warnings,
      ms,
      maxWords: req.maxWords,
      words: countWords(s.text),
      claims: s.claims.length,
      rejections: logs.slice(before).filter((l) => l.includes('rejected')).map((l) => l.replace(/^segment \S+ \S+: /, '')),
      text: s.text,
      sourceUrls: s.sourceUrls,
    };
    samples.push(sample);
    console.log(`${sample.kind.padEnd(9)} ${sample.poi.slice(0, 36).padEnd(36)} ${sample.origin.padEnd(8)} ${sample.firstPass ? '1st' : '   '} ${String(sample.words).padStart(3)}/${sample.maxWords} words ${(ms / 1000).toFixed(1).padStart(5)} s ${sample.warnings.join(',')}`);
  }
}

const stats = (list) => {
  const ai = list.filter((s) => s.origin === 'ai');
  const times = ai.map((s) => s.ms).sort((a, b) => a - b);
  const pct = (n) => Math.round((100 * n) / Math.max(1, list.length));
  return {
    n: list.length,
    firstPassPct: pct(list.filter((s) => s.firstPass).length),
    aiPct: pct(ai.length),
    templatePct: pct(list.length - ai.length),
    medianMs: times[Math.floor(times.length / 2)] ?? null,
    maxMs: times.at(-1) ?? null,
    wordsOfBudgetPct: ai.length ? Math.round((100 * ai.reduce((n, s) => n + s.words / s.maxWords, 0)) / ai.length) : null,
    avgClaims: ai.length ? +(ai.reduce((n, s) => n + s.claims, 0) / ai.length).toFixed(1) : null,
  };
};
const byKind = Object.fromEntries(Object.keys(BUDGET).map((k) => [k, stats(samples.filter((s) => s.kind === k))]));
const total = stats(samples);

const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
const outDir = path.resolve(SERVER_DIR, opts.out);
mkdirSync(outDir, { recursive: true });
const meta = { at: new Date().toISOString(), model: llm.model, promptVersion: PROMPT_VERSION, coldStartMs, budgets: BUDGET };
writeFileSync(path.join(outDir, `eval-${stamp}.json`), JSON.stringify({ meta, total, byKind, samples, systemPrompt: SYSTEM_PROMPT }, null, 1));

const row = (name, s) =>
  `| ${name} | ${s.n} | ${s.firstPassPct}% | ${s.aiPct}% | ${s.templatePct}% | ${s.medianMs !== null ? (s.medianMs / 1000).toFixed(1) : '–'} s | ${s.maxMs !== null ? (s.maxMs / 1000).toFixed(1) : '–'} s | ${s.wordsOfBudgetPct ?? '–'}% | ${s.avgClaims ?? '–'} |`;
const table = [
  '| typ | n | walidacja za 1. razem | AI (po retry) | szablon | mediana czasu | max czasu | długość / budżet | claims |',
  '|---|---|---|---|---|---|---|---|---|',
  ...Object.entries(byKind).map(([k, s]) => row(k, s)),
  row('**razem**', total),
].join('\n');
const review = [
  `# Ewaluacja AI ${meta.at}`,
  '',
  `Model \`${meta.model}\`, prompt \`${meta.promptVersion}\`, zimny start ${(coldStartMs / 1000).toFixed(0)} s.`,
  '',
  table,
  '',
  '## Teksty do oceny ręcznej (1–5)',
  '',
  'P = poprawność względem źródła, F = płynność polszczyzny, G = „przewodnikowość” (czy brzmi jak przewodnik w drodze).',
  '',
  ...samples.flatMap((s, i) => [
    `### ${i + 1}. ${s.kind} · ${s.fromPoi ? `${s.fromPoi} → ` : ''}${s.poi} · ${s.origin}${s.firstPass ? '' : ` (${s.warnings.join(', ')})`}`,
    '',
    `> ${s.text}`,
    '',
    `Źródło: ${s.sourceUrls.join(', ')} · ${s.words}/${s.maxWords} słów · ${(s.ms / 1000).toFixed(1)} s`,
    ...(s.rejections.length ? ['', `Odrzucenia walidatora: ${s.rejections.join(' | ')}`] : []),
    '',
    '| P | F | G | uwagi |',
    '|---|---|---|---|',
    '|   |   |   |   |',
    '',
  ]),
].join('\n');
writeFileSync(path.join(outDir, `review-${stamp}.md`), review);
console.log(`\n${table}\n\nwrote ${path.relative(SERVER_DIR, outDir)}/eval-${stamp}.json and review-${stamp}.md`);
