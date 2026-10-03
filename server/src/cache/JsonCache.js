// Key-value cache with TTL, kept in memory and mirrored to one JSON file so it survives restarts.
// Expired entries are still returned by getStale(): when Wikipedia is down, old data beats no data.
import { mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import path from 'node:path';

export class JsonCache {
  /**
   * @param {{ file?: string | null, ttlMs: number, now?: () => number }} opts
   *   file = null keeps the cache in memory only (tests).
   */
  constructor({ file = null, ttlMs, now = Date.now }) {
    this.file = file;
    this.ttlMs = ttlMs;
    this.now = now;
    this.entries = new Map();
    this.#load();
  }

  get(key) {
    const e = this.entries.get(key);
    return e && this.now() - e.at < this.ttlMs ? e.value : undefined;
  }

  getStale(key) {
    return this.entries.get(key)?.value;
  }

  set(key, value) {
    this.entries.set(key, { at: this.now(), value });
    this.#save();
  }

  #load() {
    if (!this.file) return;
    try {
      const data = JSON.parse(readFileSync(this.file, 'utf8'));
      for (const [k, e] of Object.entries(data)) this.entries.set(k, e);
    } catch {
      // missing or corrupt file: start empty
    }
  }

  #save() {
    if (!this.file) return;
    try {
      mkdirSync(path.dirname(this.file), { recursive: true });
      const tmp = `${this.file}.tmp`;
      writeFileSync(tmp, JSON.stringify(Object.fromEntries(this.entries)));
      renameSync(tmp, this.file);
    } catch (err) {
      console.warn(`cache: cannot write ${this.file}: ${err.message}`);
    }
  }
}
