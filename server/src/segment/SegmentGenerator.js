// POST /v1/segment logic (#18): source text from the POI registry -> prompt per kind -> Bielik (JSON Schema)
// -> grounding validator -> 1 retry -> template. Always returns a Segment (docs/CONTRACTS.md), even when the
// LLM is down; failures are reported in `warnings`.
import { createHash } from 'node:crypto';
import { HttpError } from '../http/http.js';
import { cleanText, countWords, validateSegment } from '../validate/grounding.js';
import { buildPrompt, numPredict, PROMPT_VERSION, retryPrompt, SEGMENT_SCHEMA, SYSTEM_PROMPT } from './prompts.js';
import { templateText } from './templates.js';

export const KINDS = ['WELCOME', 'APPROACH', 'ARRIVAL', 'BRIDGE', 'DEEP_DIVE', 'MISSED'];
export const INTERESTS = ['architektura', 'historia', 'sztuka', 'ludzie', 'legendy'];
const TEMPLATE_ONLY = new Set(['APPROACH', 'MISSED']);
const MAX_WORDS_RANGE = [5, 400];
const SHORT_SUMMARY_CHARS = 600;
export const MAX_WORDS_BUCKET = 10;

/** Checks the request body; the client never sends source text (prompt-injection guard), unknown fields are ignored. */
export function parseSegmentRequest(body) {
  const bad = (msg) => new HttpError(400, 'invalid_params', msg);
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw bad('body must be a JSON object');
  const { kind, poiId, fromPoiId = null, interests = [], maxWords, voice = false } = body;
  if (!KINDS.includes(kind)) throw bad(`kind must be one of ${KINDS.join(', ')}`);
  if (typeof poiId !== 'string' || !poiId) throw bad('poiId must be a non-empty string');
  if (kind === 'BRIDGE' && (typeof fromPoiId !== 'string' || !fromPoiId)) throw bad('BRIDGE needs fromPoiId');
  if (fromPoiId !== null && typeof fromPoiId !== 'string') throw bad('fromPoiId must be a string or null');
  if (!Array.isArray(interests) || interests.some((i) => !INTERESTS.includes(i))) {
    throw bad(`interests must be a subset of ${INTERESTS.join(', ')}`);
  }
  if (!Number.isInteger(maxWords) || maxWords < MAX_WORDS_RANGE[0] || maxWords > MAX_WORDS_RANGE[1]) {
    throw bad(`maxWords must be an integer in [${MAX_WORDS_RANGE.join(', ')}]`);
  }
  if (typeof voice !== 'boolean') throw bad('voice must be a boolean');
  return {
    kind,
    poiId,
    fromPoiId: kind === 'BRIDGE' ? fromPoiId : null,
    interests: [...new Set(interests)].sort(),
    // rounded up to a multiple of 10: the planner's budget changes with every GPS fix, and without buckets
    // almost no request would hit the cache filled by `npm run warm`
    maxWords: Math.ceil(maxWords / MAX_WORDS_BUCKET) * MAX_WORDS_BUCKET,
    voice,
  };
}

export class SegmentGenerator {
  /**
   * @param {{
   *   poiService: import('../pois/PoiService.js').PoiService,
   *   llm: import('../llm/OllamaClient.js').OllamaClient | null,   null = no LLM configured, templates only
   *   cache: import('../cache/JsonCache.js').JsonCache,
   *   tts?: import('../tts/TtsService.js').TtsService | null,   null = no voice, `tts_unavailable`
   *   cloudVoiceForTemplates?: boolean,   false: template segments are voiced by Piper only (saves ElevenLabs characters)
   *   timeouts?: { default: number, deepDive: number },
   *   log?: (msg: string) => void,
   * }} deps
   */
  constructor({ poiService, llm, cache, tts = null, cloudVoiceForTemplates = false, timeouts = { default: 45_000, deepDive: 90_000 }, log = () => {} }) {
    this.poiService = poiService;
    this.llm = llm;
    this.cache = cache;
    this.tts = tts;
    this.cloudVoiceForTemplates = cloudVoiceForTemplates;
    this.timeouts = timeouts;
    this.log = log;
    this.inFlight = new Map();   // the app prefetches; identical concurrent requests share one LLM call
  }

  /** @param {ReturnType<typeof parseSegmentRequest>} req */
  async generate(req) {
    const poi = this.poiService.get(req.poiId);
    if (!poi) throw new HttpError(404, 'unknown_poi', `unknown poiId ${req.poiId}`);
    const fromPoi = req.fromPoiId ? this.poiService.get(req.fromPoiId) : null;
    if (req.fromPoiId && !fromPoi) throw new HttpError(404, 'unknown_poi', `unknown fromPoiId ${req.fromPoiId}`);

    const id = segmentId(req, this.llm?.model ?? 'template');
    const cached = this.cache.get(id);
    if (cached) return this.#withVoice(cached, req);
    if (!this.inFlight.has(id)) {
      const job = this.#build(id, req, poi, fromPoi).finally(() => this.inFlight.delete(id));
      this.inFlight.set(id, job);
    }
    return this.#withVoice(await this.inFlight.get(id), req);
  }

  /** Adds audio (#19). The text segment is cached on its own, so a TTS outage never costs another LLM call. */
  async #withVoice(segment, req) {
    const out = { ...segment, audioUrl: null, durationMs: null, voice: null, warnings: [...segment.warnings] };
    if (!req.voice) return out;
    if (!this.tts) {
      out.warnings.push('tts_unavailable');
      return out;
    }
    const allowCloud = segment.origin === 'ai' || this.cloudVoiceForTemplates;
    const audio = await this.tts.speak(segment.text, { allowCloud });
    if (audio.audioId) {
      out.audioUrl = `/v1/audio/${audio.audioId}.mp3`;
      out.durationMs = audio.durationMs;
      out.voice = audio.voice;
    }
    out.warnings.push(...audio.warnings);
    return out;
  }

  async #build(id, req, poi, fromPoi) {
    const sourceUrls = fromPoi ? [fromPoi.sourceUrl, poi.sourceUrl] : [poi.sourceUrl];
    const base = { id, kind: req.kind, poiId: req.poiId, fromPoiId: req.fromPoiId, sourceUrls };
    const template = (warnings) => ({
      ...base, text: templateText(req, poi, fromPoi), claims: [], origin: 'template', llmModel: null, warnings,
    });

    if (TEMPLATE_ONLY.has(req.kind)) return template([]);
    if (!this.llm) return template(['llm_unavailable']);

    // DEEP_DIVE always, other kinds when the summary is too short to talk about (e.g. Barbakan: 198 chars):
    // the article text, so the model does not fill the gaps itself.
    const richer = async (p, always) => {
      if (!always && p.summary.length >= SHORT_SUMMARY_CHARS) return p.summary;
      const deep = await this.poiService.deepSource(p.id);
      return deep?.text && deep.text.length > p.summary.length ? deep.text : p.summary;
    };
    const source = {
      target: await richer(poi, req.kind === 'DEEP_DIVE'),
      from: fromPoi ? await richer(fromPoi, false) : undefined,
    };
    const { user, sourceText } = buildPrompt(req, poi, fromPoi, source);
    const timeoutMs = req.kind === 'DEEP_DIVE' ? this.timeouts.deepDive : this.timeouts.default;
    const maxWords = req.maxWords;
    const warnings = [];

    let prompt = user;
    for (let attempt = 1; attempt <= 2; attempt++) {
      let content;
      try {
        ({ content } = await this.llm.chat({
          system: SYSTEM_PROMPT, user: prompt, schema: SEGMENT_SCHEMA,
          numPredict: numPredict(req.kind === 'DEEP_DIVE' ? maxWords * 1.6 : maxWords), timeoutMs,
        }));
      } catch (err) {
        this.log(`segment ${req.kind} ${req.poiId}: llm ${err.code ?? err.name}: ${err.message}`);
        // Ollama on Modal sometimes answers a JSON-Schema request with a quick HTTP 500: one more try is cheap.
        // No retry after a timeout or when unreachable: the client's deadline would pass anyway.
        if (attempt === 1 && err.status >= 500) {
          warnings.push('llm_retry');
          continue;
        }
        return template([...warnings, err.code === 'timeout' ? 'llm_timeout' : 'llm_unavailable']);
      }
      let parsed = null;
      try {
        parsed = JSON.parse(content);
        if (typeof parsed?.text === 'string') parsed.text = cleanText(parsed.text);
      } catch {
        // invalid JSON counts as a failed validation
      }
      const check = parsed ? validateSegment(parsed, sourceText, { maxWords }) : { ok: false, problems: ['invalid_json'] };
      if (check.ok) {
        const segment = {
          ...base,
          text: parsed.text,
          claims: check.claims,
          origin: 'ai',
          llmModel: this.llm.model,
          warnings,
        };
        this.cache.set(id, segment);   // only AI text is cached: after an outage the next request tries the LLM again
        this.log(`segment ${req.kind} ${req.poiId}: ai, ${countWords(segment.text)} words, attempt ${attempt}`);
        return segment;
      }
      this.log(`segment ${req.kind} ${req.poiId}: attempt ${attempt} rejected (${check.problems.join('; ')})`);
      if (attempt === 1) {
        warnings.push('validation_retry');
        prompt = retryPrompt(user, check.problems);
      }
    }
    return template([...warnings, 'validation_failed']);
  }
}

/** Stable id = hash of the cache key from docs/ARCHITECTURE.md §3. Audio is keyed separately by hash(voice, text). */
export function segmentId(req, model) {
  const key = [req.kind, req.poiId, req.fromPoiId ?? '', req.interests.join(','), req.maxWords, PROMPT_VERSION, model].join('|');
  return createHash('sha256').update(key).digest('hex').slice(0, 20);
}
