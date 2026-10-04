// Voice for segments (#19): provider chain from TTS_PROVIDER (elevenlabs -> piper -> none), MP3 files in
// CACHE_DIR/audio/ keyed by hash(voice, text), so the same text is never paid for twice.
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, renameSync, writeFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { mp3DurationMs } from './mp3.js';

const QUOTA_COOLDOWN_MS = 10 * 60 * 1000;

export function audioId(voice, text) {
  return createHash('sha256').update(`${voice}\n${text}`).digest('hex').slice(0, 24);
}

export class AudioStore {
  /** @param {{ dir: string, meta: import('../cache/JsonCache.js').JsonCache }} opts meta: id -> { durationMs, voice } */
  constructor({ dir, meta }) {
    this.dir = dir;
    this.meta = meta;
  }

  file(id) {
    return path.join(this.dir, `${id}.mp3`);
  }

  get(id) {
    const m = this.meta.getStale(id);
    return m && existsSync(this.file(id)) ? m : null;
  }

  put(id, mp3, info) {
    mkdirSync(this.dir, { recursive: true });
    const tmp = `${this.file(id)}.tmp`;
    writeFileSync(tmp, mp3);
    renameSync(tmp, this.file(id));
    this.meta.set(id, info);
  }

  read(id) {
    return this.get(id) ? readFileSync(this.file(id)) : null;
  }
}

export class TtsService {
  /**
   * @param {{ providers: (import('./providers.js').ElevenLabsTts | import('./providers.js').PiperTts)[],
   *           store: AudioStore, log?: (msg: string) => void, now?: () => number }} opts
   *   providers in fallback order; empty = TTS_PROVIDER=none
   */
  constructor({ providers, store, log = () => {}, now = Date.now }) {
    this.providers = providers;
    this.store = store;
    this.log = log;
    this.now = now;
    this.disabledUntil = new Map();
    this.inFlight = new Map();
  }

  /**
   * @param {string} text
   * @param {{ allowCloud: boolean }} opts allowCloud = false skips paid providers (template segments go to Piper)
   * @returns {Promise<{ audioId: string|null, durationMs: number|null, voice: string|null, warnings: string[] }>}
   */
  async speak(text, { allowCloud }) {
    const policy = this.providers.filter((p) => allowCloud || !p.cloud);
    // fallback warning only against the policy chain: a template sent to Piper on purpose is not a fallback
    const chain = policy.filter((p) => p.available());
    const warn = (used) => (policy[0] && policy[0] !== used ? [`tts_fallback_${used.name}`] : []);
    for (const p of chain) {
      const id = audioId(p.voice, text);
      const hit = this.store.get(id);
      if (hit) return { audioId: id, durationMs: hit.durationMs, voice: hit.voice, warnings: warn(p) };
    }
    for (const p of chain) {
      if ((this.disabledUntil.get(p.name) ?? 0) > this.now()) continue;
      const id = audioId(p.voice, text);
      try {
        if (!this.inFlight.has(id)) {
          this.inFlight.set(id, this.#synthesize(p, id, text).finally(() => this.inFlight.delete(id)));
        }
        const info = await this.inFlight.get(id);
        return { audioId: id, ...info, warnings: warn(p) };
      } catch (err) {
        this.log(`tts ${p.name}: ${err.code ?? err.name}: ${err.message}`);
        if (err.code === 'quota') this.disabledUntil.set(p.name, this.now() + QUOTA_COOLDOWN_MS);
      }
    }
    return { audioId: null, durationMs: null, voice: null, warnings: ['tts_unavailable'] };
  }

  async #synthesize(provider, id, text) {
    const mp3 = await provider.synthesize(text);
    const info = { durationMs: mp3DurationMs(mp3), voice: provider.voice };
    if (!info.durationMs) throw Object.assign(new Error('provider returned no MP3 frames'), { code: 'unavailable' });
    this.store.put(id, mp3, info);
    this.log(`tts ${provider.name}: ${text.length} chars -> ${info.durationMs} ms`);
    return info;
  }

  /** For /v1/health; no network calls. */
  health() {
    const p = this.providers.find((x) => x.available() && (this.disabledUntil.get(x.name) ?? 0) <= this.now());
    return { ok: Boolean(p), provider: p?.name ?? 'none' };
  }
}
