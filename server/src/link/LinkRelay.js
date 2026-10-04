// Phone <-> watch link through the laptop server (#51). On the emulators Super Device finds no devices, but
// both reach this server over HTTP (`hdc rport tcp:8787 tcp:8787`), so the devices exchange messages here.
// Messages live in memory only: max 200 per room, 10 min TTL, never written to disk or to the log.
// The relay refuses position fields: the link carries guide state, not where the user is (#56).

export const ROOM_RE = /^[A-Za-z0-9_-]{1,32}$/;
export const MAX_MESSAGES = 200;
export const TTL_MS = 10 * 60 * 1000;
export const MAX_ROOMS = 100;
export const MAX_BODY_BYTES = 4 * 1024;

const POSITION_KEYS = new Set(['lat', 'lon', 'lng', 'latitude', 'longitude', 'position', 'coords', 'coordinates', 'geofix', 'accuracym']);

/** Key name of the first position-like field anywhere in the value, or null. */
export function findPositionKey(value, depth = 0) {
  if (!value || typeof value !== 'object' || depth > 8) return null;
  for (const [k, v] of Object.entries(value)) {
    if (POSITION_KEYS.has(k.toLowerCase())) return k;
    const inner = findPositionKey(v, depth + 1);
    if (inner) return inner;
  }
  return null;
}

export class LinkRelay {
  /** @param {{ now?: () => number }} [opts] */
  constructor({ now = Date.now } = {}) {
    this.now = now;
    /** @type {Map<string, { lastSeq: number, messages: { seq: number, t: number, from: string, body: object }[] }>} */
    this.rooms = new Map();
  }

  /** @returns {{ seq: number, t: number }} */
  post(room, from, body) {
    this.#expire();
    let r = this.rooms.get(room);
    if (!r) {
      if (this.rooms.size >= MAX_ROOMS) throw Object.assign(new Error('too many rooms'), { code: 'too_many_rooms' });
      r = { lastSeq: 0, messages: [] };
      this.rooms.set(room, r);
    }
    const msg = { seq: ++r.lastSeq, t: this.now(), from, body };
    r.messages.push(msg);
    if (r.messages.length > MAX_MESSAGES) r.messages.splice(0, r.messages.length - MAX_MESSAGES);
    return { seq: msg.seq, t: msg.t };
  }

  /** Messages with seq > after. `lastSeq` lets a client that missed expired messages jump forward. */
  list(room, after = 0) {
    this.#expire();
    const r = this.rooms.get(room);
    if (!r) return { messages: [], lastSeq: 0 };
    return { messages: r.messages.filter((m) => m.seq > after), lastSeq: r.lastSeq };
  }

  #expire() {
    const cutoff = this.now() - TTL_MS;
    for (const [id, r] of this.rooms) {
      const i = r.messages.findIndex((m) => m.t > cutoff);
      if (i === -1) this.rooms.delete(id);
      else if (i > 0) r.messages.splice(0, i);
    }
  }
}
