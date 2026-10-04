// Text-to-speech providers (#19). Each returns MP3 bytes: AVPlayer plays MP3/M4A, not raw PCM.
import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';

export class TtsError extends Error {
  /** @param {'quota'|'timeout'|'unavailable'} code quota = out of characters or key rejected: stop calling for a while */
  constructor(code, message) {
    super(message);
    this.name = 'TtsError';
    this.code = code;
  }
}

export class ElevenLabsTts {
  name = 'elevenlabs';
  cloud = true;

  /** @param {{ apiKey: string, voiceId: string, modelId?: string, timeoutMs?: number, fetch?: typeof fetch }} opts */
  constructor({ apiKey, voiceId, modelId = 'eleven_multilingual_v2', timeoutMs = 20_000, fetch = globalThis.fetch }) {
    Object.assign(this, { apiKey, voiceId, modelId, timeoutMs, fetch });
    this.voice = `elevenlabs:${voiceId}`;
  }

  available() {
    return Boolean(this.apiKey && this.voiceId);
  }

  /** Only the generated text about the place is sent: no position, no user data. */
  async synthesize(text) {
    let res;
    try {
      res = await this.fetch(`https://api.elevenlabs.io/v1/text-to-speech/${this.voiceId}?output_format=mp3_44100_128`, {
        method: 'POST',
        headers: { 'xi-api-key': this.apiKey, 'Content-Type': 'application/json', Accept: 'audio/mpeg' },
        body: JSON.stringify({ text, model_id: this.modelId, language_code: 'pl' }),
        signal: AbortSignal.timeout(this.timeoutMs),
      });
    } catch (err) {
      if (err.name === 'TimeoutError' || err.name === 'AbortError') throw new TtsError('timeout', `ElevenLabs over ${this.timeoutMs} ms`);
      throw new TtsError('unavailable', `ElevenLabs unreachable: ${err.message}`);
    }
    if (!res.ok) {
      const detail = (await res.text().catch(() => '')).slice(0, 200);
      // 401 quota_exceeded / invalid key, 402 paid plan required, 429 too many requests
      throw new TtsError([401, 402, 429].includes(res.status) ? 'quota' : 'unavailable', `ElevenLabs HTTP ${res.status} ${detail}`.trim());
    }
    return Buffer.from(await res.arrayBuffer());
  }
}

export class PiperTts {
  name = 'piper';
  cloud = false;

  /** @param {{ bin: string, voicePath: string, ffmpeg: string, timeoutMs?: number, run?: typeof runProcess }} opts */
  constructor({ bin, voicePath, ffmpeg, timeoutMs = 20_000, run = runProcess }) {
    Object.assign(this, { bin, voicePath, ffmpeg, timeoutMs, run });
    this.voice = `piper:${path.basename(voicePath, '.onnx')}`;
  }

  available() {
    return existsSync(this.voicePath) && (!path.isAbsolute(this.bin) || existsSync(this.bin));
  }

  /** Piper writes WAV; ffmpeg turns it into MP3 on stdout. */
  async synthesize(text) {
    const dir = mkdtempSync(path.join(os.tmpdir(), 'piper-'));
    const wav = path.join(dir, 'out.wav');
    try {
      await this.run(this.bin, ['--model', this.voicePath, '--output_file', wav], text, this.timeoutMs);
      return await this.run(this.ffmpeg, ['-loglevel', 'error', '-i', wav, '-codec:a', 'libmp3lame', '-q:a', '4', '-f', 'mp3', 'pipe:1'], '', this.timeoutMs);
    } catch (err) {
      throw new TtsError(err.code === 'timeout' ? 'timeout' : 'unavailable', `Piper: ${err.message}`);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }
}

/** Runs a command with `input` on stdin (UTF-8); resolves with stdout bytes. */
export function runProcess(cmd, args, input, timeoutMs) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
    const out = [];
    let err = '';
    const timer = setTimeout(() => {
      p.kill();
      reject(Object.assign(new Error(`${path.basename(cmd)} over ${timeoutMs} ms`), { code: 'timeout' }));
    }, timeoutMs);
    p.stdout.on('data', (d) => out.push(d));
    p.stderr.on('data', (d) => (err += d));
    p.on('error', (e) => {
      clearTimeout(timer);
      reject(e);
    });
    p.on('close', (code) => {
      clearTimeout(timer);
      if (code === 0) resolve(Buffer.concat(out));
      else reject(new Error(`${path.basename(cmd)} exited ${code}: ${err.slice(-300)}`));
    });
    p.stdin.end(input, 'utf8');
  });
}
