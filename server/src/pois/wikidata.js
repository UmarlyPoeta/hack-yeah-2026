// Wikidata entities via wbgetentities (not SPARQL: rate-limited during the hackathon).
import { USER_AGENT } from './wikipedia.js';

export class WikidataClient {
  /** @param {{ apiUrl: string, timeoutMs: number, fetch?: typeof fetch }} opts */
  constructor({ apiUrl, timeoutMs, fetch: fetchImpl = globalThis.fetch }) {
    this.apiUrl = apiUrl;
    this.timeoutMs = timeoutMs;
    this.fetch = fetchImpl;
  }

  /** P31 (instance of) and P361 (part of) target ids per entity id. */
  async claims(qids) {
    const out = new Map();
    const unique = [...new Set(qids)];
    for (let i = 0; i < unique.length; i += 50) {
      const params = new URLSearchParams({
        action: 'wbgetentities', format: 'json', props: 'claims', ids: unique.slice(i, i + 50).join('|'),
      });
      const res = await this.fetch(`${this.apiUrl}?${params}`, {
        headers: { 'User-Agent': USER_AGENT, 'Api-User-Agent': USER_AGENT },
        signal: AbortSignal.timeout(this.timeoutMs),
      });
      if (!res.ok) throw new Error(`wikidata http ${res.status}`);
      const data = await res.json();
      if (data.error) throw new Error(`wikidata api ${data.error.code}`);
      for (const [qid, e] of Object.entries(data.entities ?? {})) {
        out.set(qid, { p31: targets(e, 'P31'), p361: targets(e, 'P361') });
      }
    }
    return out;
  }
}

function targets(entity, prop) {
  return (entity.claims?.[prop] ?? [])
    .map((s) => s.mainsnak?.datavalue?.value?.id)
    .filter((id) => typeof id === 'string');
}
