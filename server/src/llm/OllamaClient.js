// Ollama /api/chat client for Bielik on Modal (server/modal/). Every request carries the Modal proxy-auth
// headers. JSON output is forced with `format` = JSON Schema.

export class LlmError extends Error {
  /** @param {'timeout'|'unavailable'|'bad_response'} code */
  constructor(code, message, status = 0) {
    super(message);
    this.name = 'LlmError';
    this.code = code;
    this.status = status;   // HTTP status for 'unavailable' responses, 0 when the request did not get through
  }
}

export class OllamaClient {
  /**
   * @param {{ url: string, model: string, modalKey?: string, modalSecret?: string, keepAlive?: string, fetch?: typeof fetch }} opts
   */
  constructor({ url, model, modalKey = '', modalSecret = '', keepAlive = '30m', fetch = globalThis.fetch }) {
    this.url = url.replace(/\/+$/, '');
    this.model = model;
    this.keepAlive = keepAlive;
    this.fetch = fetch;
    this.headers = { 'Content-Type': 'application/json' };
    if (modalKey) {
      this.headers['Modal-Key'] = modalKey;
      this.headers['Modal-Secret'] = modalSecret;
    }
    /** @type {{ at: number, ok: boolean } | null} result of the last real request, for /v1/health */
    this.last = null;
  }

  /**
   * @param {{ system: string, user: string, schema: object, numPredict: number, timeoutMs: number, temperature?: number }} req
   * @returns {Promise<{ content: string, evalCount: number, ms: number }>}
   */
  async chat({ system, user, schema, numPredict, timeoutMs, temperature = 0.2 }) {
    const started = Date.now();
    let res;
    try {
      res = await this.fetch(`${this.url}/api/chat`, {
        method: 'POST',
        headers: this.headers,
        body: JSON.stringify({
          model: this.model,
          messages: [
            { role: 'system', content: system },
            { role: 'user', content: user },
          ],
          format: schema,
          stream: false,
          keep_alive: this.keepAlive,
          options: { temperature, num_predict: numPredict },
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
    const content = body?.message?.content;
    if (typeof content !== 'string') throw new LlmError('bad_response', 'LLM response has no message.content');
    return { content, evalCount: body.eval_count ?? 0, ms: Date.now() - started };
  }

  /**
   * For /v1/health. Does not call Modal: a probe would wake the GPU container (and bill it) every time
   * the app polls health. Reports the configuration and the outcome of the last real request.
   */
  health() {
    return { ok: Boolean(this.url && this.model) && this.last?.ok !== false, model: this.model };
  }
}
