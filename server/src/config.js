// Server configuration from environment variables (see server/.env.example).
// `npm start` loads server/.env through `node --env-file-if-exists`.
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SERVER_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const pkg = JSON.parse(readFileSync(path.join(SERVER_DIR, 'package.json'), 'utf8'));

export const VERSION = pkg.version;

export function loadConfig(env = process.env) {
  return {
    port: intOr(env.PORT, 8787),
    host: env.HOST || '0.0.0.0',
    cacheDir: path.resolve(SERVER_DIR, env.CACHE_DIR || './.cache'),
    fixturePoisPath: path.resolve(SERVER_DIR, env.FIXTURE_POIS || '../fixtures/pois-krakow.json'),
    wikiApiUrl: env.WIKI_API_URL || 'https://pl.wikipedia.org/w/api.php',
    wikidataApiUrl: env.WIKIDATA_API_URL || 'https://www.wikidata.org/w/api.php',
    wikiTimeoutMs: intOr(env.WIKI_TIMEOUT_MS, 8000),
    poiCacheTtlMs: intOr(env.POI_CACHE_TTL_MS, 24 * 3600 * 1000),
    // read by P4 modules (LLM, TTS); kept here so there is one config object.
    // Bielik runs in Ollama on Modal (server/modal/): every LLM request needs the Modal-Key / Modal-Secret headers.
    ollamaUrl: env.OLLAMA_URL || 'http://localhost:11434',
    llmModel: env.LLM_MODEL || '',
    modalKey: env.MODAL_KEY || '',
    modalSecret: env.MODAL_SECRET || '',
    ttsProvider: env.TTS_PROVIDER || 'none',
    elevenLabsApiKey: env.ELEVENLABS_API_KEY || '',
    elevenLabsVoiceId: env.ELEVENLABS_VOICE_ID || '',
    elevenLabsModelId: env.ELEVENLABS_MODEL_ID || 'eleven_multilingual_v2',
    piperBin: env.PIPER_BIN || 'piper',
    piperVoice: path.resolve(SERVER_DIR, env.PIPER_VOICE || './voices/pl_PL-gosia-medium.onnx'),
    ffmpegBin: env.FFMPEG_BIN || 'ffmpeg',
    ttsTimeoutMs: intOr(env.TTS_TIMEOUT_MS, 20_000),
    // false: template segments get Piper only, ElevenLabs characters go to AI text (free plan: 10k/month)
    ttsCloudForTemplates: env.TTS_CLOUD_FOR_TEMPLATES === 'true',
    llmTimeoutMs: intOr(env.LLM_TIMEOUT_MS, 45_000),
    llmDeepDiveTimeoutMs: intOr(env.LLM_DEEP_DIVE_TIMEOUT_MS, 90_000),
  };
}

function intOr(value, fallback) {
  const n = Number.parseInt(value ?? '', 10);
  return Number.isFinite(n) ? n : fallback;
}
