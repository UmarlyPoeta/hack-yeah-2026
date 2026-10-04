// Anthropic Messages API client with the same interface as OllamaClient (chat + health + model), so
// SegmentGenerator works with either. LLM_PROVIDER=claude selects it (src/services.js).
// JSON output: the segment schema is offered as the only tool and the model is forced to call it;
// the tool input is the JSON object Bielik would have returned as message content.
import { LlmError } from './OllamaClient.js';

const API_URL = 'https://api.anthropic.com/v1/messages';
const API_VERSION = '2023-06-01';
const TOOL_NAME = 'segment';

export class ClaudeClient {
  /**
   * @param {{ apiKey: string, model: string, url?: string, fetch?: typeof fetch }} opts
   */
  constructor({ apiKey, model, url = API_URL, fetch = globalThis.fetch }) {
    this.apiKey = apiKey;
    this.model = model;
    this.url = url;
    this.fetch = fetch;
    /** @type {{ at: number, ok: boolean } | null} */
    this.last = null;
    /** tokens used since start, for the log (the budget is small) */
    this.usage = { input: 0, output: 0 };
  }

  /**
   * @param {{ system: string, user: string, schema: object, numPredict: number, timeoutMs: number, temperature?: number }} req
   * @returns {Promise<{ content: string, evalCount: number, ms: number }>}
   */
  async chat({ system, user, schema, numPredict, timeoutMs, temperature = 0.2 }) {
    const started = Date.now();
    let res;
    try {
      res = await this.fetch(this.url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': this.apiKey,
          'anthropic-version': API_VERSION,
        },
        body: JSON.stringify({
          model: this.model,
          // numPredict is sized for Bielik's tokenizer; the tool call adds JSON keys and escaping
          max_tokens: Math.max(600, Math.ceil(numPredict * 2)),
          temperature,
          system,
          messages: [{ role: 'user', content: user }],
          tools: [{ name: TOOL_NAME, description: 'Zwróć gotowy fragment narracji.', input_schema: schema }],
          tool_choice: { type: 'tool', name: TOOL_NAME },
        }),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (err) {
      this.last = { at: Date.now(), ok: false };
      if (err.name === 'TimeoutError' || err.name === 'AbortError') throw new LlmError('timeout', `LLM over ${timeoutMs} ms`);
      throw new LlmError('unavailable', `LLM unreachable: ${err.message}`);
    }
    if (!res.ok) {
      this.last = { at: Date.now(), ok: false };
      const detail = (await res.text().catch(() => '')).slice(0, 200);
      throw new LlmError('unavailable', `LLM HTTP ${res.status} ${detail}`.trim(), res.status);
    }
    let body;
    try {
      body = await res.json();
    } catch {
      throw new LlmError('bad_response', 'LLM response is not JSON');
    }
    this.last = { at: Date.now(), ok: true };
    const call = Array.isArray(body?.content) ? body.content.find((b) => b.type === 'tool_use' && b.name === TOOL_NAME) : null;
    if (!call || typeof call.input !== 'object') throw new LlmError('bad_response', 'LLM response has no segment tool call');
    this.usage.input += body.usage?.input_tokens ?? 0;
    this.usage.output += body.usage?.output_tokens ?? 0;
    return { content: JSON.stringify(call.input), evalCount: body.usage?.output_tokens ?? 0, ms: Date.now() - started };
  }

  /** For /v1/health: configuration and the last real request; no probe, every call costs tokens. */
  health() {
    return { ok: Boolean(this.apiKey && this.model) && this.last?.ok !== false, model: this.model };
  }
}
