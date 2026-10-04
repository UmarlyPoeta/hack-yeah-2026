// Routes for createApp({ routes }): the phone <-> watch relay (#51).
//   POST /v1/link/<room>/messages   { from: "phone"|"watch"|..., body: {...} }  -> 200 { seq, t }
//   GET  /v1/link/<room>/messages?after=<seq>                                    -> 200 { messages, lastSeq }
// <room> is the pairing code (the phone shows 4 digits, the watch types them in).
import { HttpError, readJson, sendJson } from '../http/http.js';
import { findPositionKey, MAX_BODY_BYTES } from './LinkRelay.js';

const PATH = /^\/v1\/link\/(?<room>[A-Za-z0-9_-]{1,32})\/messages$/;
const FROM_RE = /^[a-z0-9_-]{1,16}$/;

/** @param {import('./LinkRelay.js').LinkRelay} relay */
export function linkRoutes(relay) {
  const bad = (msg) => new HttpError(400, 'invalid_params', msg);
  return [
    {
      method: 'POST',
      path: PATH,
      handler: async (req, res, { params }) => {
        const msg = await readJson(req, MAX_BODY_BYTES);
        if (!msg || typeof msg !== 'object' || Array.isArray(msg)) throw bad('body must be a JSON object');
        if (typeof msg.from !== 'string' || !FROM_RE.test(msg.from)) throw bad('from must match [a-z0-9_-]{1,16}');
        if (!msg.body || typeof msg.body !== 'object' || Array.isArray(msg.body)) throw bad('body.body must be a JSON object');
        const key = findPositionKey(msg.body);
        if (key) throw new HttpError(400, 'position_not_allowed', `the link does not carry positions (field "${key}")`);
        try {
          sendJson(res, 200, relay.post(params.room, msg.from, msg.body));
        } catch (err) {
          if (err.code === 'too_many_rooms') throw new HttpError(503, 'too_many_rooms', 'too many active rooms, try again later');
          throw err;
        }
      },
    },
    {
      method: 'GET',
      path: PATH,
      handler: async (_req, res, { url, params }) => {
        const raw = url.searchParams.get('after') ?? '0';
        const after = /^\d{1,9}$/.test(raw) ? Number(raw) : NaN;
        if (Number.isNaN(after)) throw bad('after must be a non-negative integer');
        sendJson(res, 200, relay.list(params.room, after));
      },
    },
  ];
}
