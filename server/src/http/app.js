// Request router for /v1/*. No framework: routes are { method, path, handler }.
// P4 adds /v1/segment and /v1/audio by passing `routes` to createApp().
import { VERSION } from '../config.js';
import { HttpError, sendError, sendJson } from './http.js';

const RADIUS_MIN = 50;
const RADIUS_MAX = 1000;
const RADIUS_DEFAULT = 300;

/**
 * @param {{
 *   poiService: import('../pois/PoiService.js').PoiService,
 *   health?: { llm?: () => Promise<{ok: boolean, model: string}>, tts?: () => Promise<{ok: boolean, provider: string}> },
 *   routes?: { method: string, path: string | RegExp, handler: (req, res, ctx) => Promise<void> | void }[],
 *   log?: (msg: string) => void,
 * }} deps
 * @returns {(req: import('node:http').IncomingMessage, res: import('node:http').ServerResponse) => Promise<void>}
 */
export function createApp({ poiService, health = {}, routes = [], log = () => {} }) {
  const table = [
    { method: 'GET', path: '/v1/health', handler: healthHandler(health) },
    { method: 'GET', path: '/v1/pois', handler: poisHandler(poiService) },
    ...routes,
  ];

  return async (req, res) => {
    const started = Date.now();
    const url = new URL(req.url ?? '/', 'http://localhost');
    try {
      const matches = table.map((r) => ({ r, m: match(r.path, url.pathname) })).filter((x) => x.m);
      if (matches.length === 0) throw new HttpError(404, 'not_found', `no route ${url.pathname}`);
      const hit = matches.find((x) => x.r.method === req.method);
      if (!hit) {
        res.setHeader('Allow', [...new Set(matches.map((x) => x.r.method))].join(', '));
        throw new HttpError(405, 'method_not_allowed', `${req.method} not allowed on ${url.pathname}`);
      }
      await hit.r.handler(req, res, { url, params: hit.m.groups ?? {} });
    } catch (err) {
      if (err instanceof HttpError) {
        if (!res.headersSent) sendError(res, err.status, err.code, err.message);
      } else {
        log(`error ${req.method} ${url.pathname}: ${err.stack ?? err}`);
        if (!res.headersSent) sendError(res, 500, 'internal', 'internal server error');
        else res.destroy();
      }
    } finally {
      // path only: query strings carry the user's position and are never logged
      log(`${req.method} ${url.pathname} ${res.statusCode} ${Date.now() - started}ms`);
    }
  };
}

function match(path, pathname) {
  if (typeof path === 'string') return path === pathname ? { groups: {} } : null;
  return path.exec(pathname);
}

function healthHandler(health) {
  return async (_req, res) => {
    const [llm, tts] = await Promise.all([
      safeCheck(health.llm, { ok: false, model: '' }),
      safeCheck(health.tts, { ok: false, provider: 'none' }),
    ]);
    sendJson(res, 200, { ok: true, version: VERSION, llm, tts });
  };
}

async function safeCheck(check, fallback) {
  if (!check) return fallback;
  try {
    return await check();
  } catch {
    return fallback;
  }
}

function poisHandler(poiService) {
  return async (_req, res, { url }) => {
    const q = url.searchParams;
    const lat = parseNumber(q.get('lat'));
    const lon = parseNumber(q.get('lon'));
    const radius = q.has('radius') ? parseNumber(q.get('radius')) : RADIUS_DEFAULT;
    if (lat === null || lat < -90 || lat > 90) throw invalid('lat must be a number in [-90, 90]');
    if (lon === null || lon < -180 || lon > 180) throw invalid('lon must be a number in [-180, 180]');
    if (radius === null || radius < RADIUS_MIN || radius > RADIUS_MAX) {
      throw invalid(`radius must be a number in [${RADIUS_MIN}, ${RADIUS_MAX}]`);
    }
    const { pois, source, warnings } = await poiService.near(lat, lon, Math.round(radius));
    sendJson(res, 200, { pois, source, warnings });
  };
}

function parseNumber(s) {
  if (s === null || s.trim() === '') return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

function invalid(message) {
  return new HttpError(400, 'invalid_params', message);
}
