// Smoke test for both TTS providers (issue #7). Reads server/.env.
//
//   node --env-file=.env scripts/tts-smoke.js voices    list Polish voices on the account + shared library
//   node --env-file=.env scripts/tts-smoke.js           ElevenLabs (if key + voice id set) and Piper -> .cache/*.mp3
//
// Never prints the API key. Writes audio to CACHE_DIR (ignored by git).
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SERVER_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const env = process.env;
const API = 'https://api.elevenlabs.io';
const CACHE = path.resolve(SERVER_DIR, env.CACHE_DIR || './.cache');
const TEXT =
  'Za około czterdzieści metrów po prawej: Kamienica Czyncielów. ' +
  'To właśnie tutaj, na przełomie tysiąc dziewięćsetnego i tysiąc dziewięćset pierwszego roku, Stanisław Wyspiański napisał Wesele.';

async function eleven(pathname, init = {}) {
  const res = await fetch(API + pathname, {
    ...init,
    headers: { 'xi-api-key': env.ELEVENLABS_API_KEY, ...(init.headers || {}) },
  });
  if (!res.ok) throw new Error(`${init.method || 'GET'} ${pathname} -> ${res.status} ${await res.text()}`);
  return res;
}

function run(cmd, args, input) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { stdio: ['pipe', 'pipe', 'pipe'] });
    let out = '';
    let err = '';
    p.stdout.on('data', (d) => (out += d));
    p.stderr.on('data', (d) => (err += d));
    p.on('error', reject);
    p.on('close', (code) => (code === 0 ? resolve(out) : reject(new Error(`${cmd} exited ${code}: ${err.slice(-500)}`))));
    p.stdin.end(input ?? '');
  });
}

async function mp3DurationMs(file) {
  const ffprobe = (env.FFMPEG_BIN || 'ffmpeg').replace(/ffmpeg(\.exe)?$/i, 'ffprobe$1');
  const out = await run(ffprobe, ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', file]);
  return Math.round(Number.parseFloat(out) * 1000);
}

async function subscription() {
  const s = await (await eleven('/v1/user/subscription')).json();
  console.log(
    `ElevenLabs plan: ${s.tier} | characters used ${s.character_count} / ${s.character_limit}` +
      ` | resets ${s.next_character_count_reset_unix ? new Date(s.next_character_count_reset_unix * 1000).toISOString() : '?'}`,
  );
}

async function listVoices() {
  await subscription();
  const mine = await (await eleven('/v2/voices?page_size=100')).json();
  const isPolish = (v) =>
    (v.labels?.language || '').toLowerCase().startsWith('pl') ||
    (v.verified_languages || []).some((l) => (l.language || '').toLowerCase() === 'pl');
  console.log('\nVoices on the account that are verified for Polish:');
  for (const v of mine.voices.filter(isPolish)) console.log(`  ${v.voice_id}  ${v.name}  [${v.category}]`);

  const shared = await (await eleven('/v1/shared-voices?language=pl&page_size=20&sort=trending')).json();
  console.log('\nShared library, Polish (add one to "My voices" in the web app before using it):');
  for (const v of shared.voices)
    console.log(`  ${v.voice_id}  ${v.name}  | ${v.gender}, ${v.age}, ${v.accent || ''} | ${v.use_case || ''} | ${v.description?.slice(0, 60) || ''}`);
}

async function elevenLabsTts() {
  if (!env.ELEVENLABS_API_KEY || !env.ELEVENLABS_VOICE_ID) {
    console.log('ElevenLabs: skipped (ELEVENLABS_API_KEY or ELEVENLABS_VOICE_ID empty in server/.env)');
    return;
  }
  await subscription();
  const t0 = Date.now();
  const res = await eleven(`/v1/text-to-speech/${env.ELEVENLABS_VOICE_ID}?output_format=mp3_44100_128`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'audio/mpeg' },
    body: JSON.stringify({ text: TEXT, model_id: env.ELEVENLABS_MODEL_ID || 'eleven_multilingual_v2', language_code: 'pl' }),
  });
  const file = path.join(CACHE, 'elevenlabs-test.mp3');
  writeFileSync(file, Buffer.from(await res.arrayBuffer()));
  const ms = Date.now() - t0;
  console.log(
    `ElevenLabs: ${file} | ${await mp3DurationMs(file)} ms of audio in ${ms} ms | ${TEXT.length} characters` +
      ` | character-cost header: ${res.headers.get('character-cost') ?? 'n/a'}`,
  );
}

async function piperTts() {
  const wav = path.join(CACHE, 'piper-test.wav');
  const mp3 = path.join(CACHE, 'piper-test.mp3');
  const voice = path.resolve(SERVER_DIR, env.PIPER_VOICE || './voices/pl_PL-gosia-medium.onnx');
  const t0 = Date.now();
  await run(env.PIPER_BIN || 'piper', ['--model', voice, '--output_file', wav], TEXT);
  await run(env.FFMPEG_BIN || 'ffmpeg', ['-y', '-loglevel', 'error', '-i', wav, '-codec:a', 'libmp3lame', '-q:a', '4', mp3]);
  rmSync(wav);
  console.log(`Piper: ${mp3} | ${await mp3DurationMs(mp3)} ms of audio in ${Date.now() - t0} ms (WAV -> MP3 included)`);
}

mkdirSync(CACHE, { recursive: true });
if (process.argv[2] === 'voices') {
  await listVoices();
} else {
  for (const step of [elevenLabsTts, piperTts]) {
    try {
      await step();
    } catch (e) {
      console.log(`${step.name}: FAIL ${e.message}`);
      process.exitCode = 1;
    }
  }
}
