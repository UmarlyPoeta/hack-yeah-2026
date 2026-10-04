// Wires the server's services from config. Shared by src/index.js and scripts/warm.js, so the warm-up fills
// exactly the caches the running server reads.
import path from 'node:path';
import { JsonCache } from './cache/JsonCache.js';
import { ClaudeClient } from './llm/ClaudeClient.js';
import { OllamaClient } from './llm/OllamaClient.js';
import { loadFixturePois, PoiService } from './pois/PoiService.js';
import { WikidataClient } from './pois/wikidata.js';
import { WikipediaClient } from './pois/wikipedia.js';
import { SegmentGenerator } from './segment/SegmentGenerator.js';
import { ElevenLabsTts, PiperTts } from './tts/providers.js';
import { AudioStore, TtsService } from './tts/TtsService.js';

const DAY_MS = 24 * 3600 * 1000;

/** TTS_PROVIDER: elevenlabs -> [ElevenLabs, Piper], piper -> [Piper], none -> []. */
export function ttsProviders(config) {
  const piper = new PiperTts({ bin: config.piperBin, voicePath: config.piperVoice, ffmpeg: config.ffmpegBin, timeoutMs: config.ttsTimeoutMs });
  if (config.ttsProvider === 'piper') return [piper];
  if (config.ttsProvider === 'elevenlabs') {
    const eleven = new ElevenLabsTts({
      apiKey: config.elevenLabsApiKey, voiceId: config.elevenLabsVoiceId, modelId: config.elevenLabsModelId, timeoutMs: config.ttsTimeoutMs,
    });
    return [eleven, piper];
  }
  return [];
}

/** LLM_PROVIDER=claude -> Anthropic API (needs ANTHROPIC_API_KEY), otherwise Bielik in Ollama (needs LLM_MODEL). */
export function createLlm(config) {
  if (config.llmProvider === 'claude') {
    return config.anthropicApiKey ? new ClaudeClient({ apiKey: config.anthropicApiKey, model: config.claudeModel }) : null;
  }
  return config.llmModel
    ? new OllamaClient({ url: config.ollamaUrl, model: config.llmModel, modalKey: config.modalKey, modalSecret: config.modalSecret })
    : null;
}

export function createServices(config, log = () => {}) {
  const poiService = new PoiService({
    wiki: new WikipediaClient({ apiUrl: config.wikiApiUrl, timeoutMs: config.wikiTimeoutMs }),
    wikidata: new WikidataClient({ apiUrl: config.wikidataApiUrl, timeoutMs: config.wikiTimeoutMs }),
    areaCache: new JsonCache({ file: path.join(config.cacheDir, 'pois-areas.json'), ttlMs: config.poiCacheTtlMs }),
    articleCache: new JsonCache({ file: path.join(config.cacheDir, 'articles.json'), ttlMs: 7 * config.poiCacheTtlMs }),
    fixturePois: loadFixturePois(config.fixturePoisPath),
    log,
  });

  const llm = createLlm(config);

  const providers = ttsProviders(config);
  const tts = providers.length
    ? new TtsService({
      providers,
      store: new AudioStore({
        dir: path.join(config.cacheDir, 'audio'),
        meta: new JsonCache({ file: path.join(config.cacheDir, 'audio.json'), ttlMs: 365 * DAY_MS }),
      }),
      log,
    })
    : null;

  const segments = new SegmentGenerator({
    poiService,
    llm,
    tts,
    cloudVoiceForTemplates: config.ttsCloudForTemplates,
    cache: new JsonCache({ file: path.join(config.cacheDir, 'segments.json'), ttlMs: 30 * DAY_MS }),
    timeouts: { default: config.llmTimeoutMs, deepDive: config.llmDeepDiveTimeoutMs },
    log,
  });

  const health = {
    llm: async () => (llm ? llm.health() : { ok: false, model: '' }),
    tts: async () => (tts ? tts.health() : { ok: false, provider: 'none' }),
  };
  return { poiService, llm, tts, segments, health };
}
