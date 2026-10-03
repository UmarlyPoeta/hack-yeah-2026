# server/

Backend for Spacer z historią. Node ≥ 22.9, no dependencies (`node:http`, `node --test`). API contract: [`docs/CONTRACTS.md`](../docs/CONTRACTS.md).

```sh
cd server
cp .env.example .env     # optional; defaults work without it
npm start                # prints localhost and LAN addresses for the emulator
npm test                 # offline: Wikipedia responses are replayed from test/fixtures/
npm run record-fixtures  # re-record test/fixtures/ from the live API (needs internet)
```

## Endpoints

| Route | Status | Owner |
|---|---|---|
| `GET /v1/health` | done (`llm`/`tts` report `ok: false` until P4 plugs in checks) | P3 |
| `GET /v1/pois?lat=&lon=&radius=` | done | P3 |
| `POST /v1/segment`, `GET /v1/audio/:id.mp3` | todo | P4 |

## `/v1/pois` data flow

1. The position is snapped to a ~100 m grid cell. One cache entry serves the whole cell (`.cache/pois-areas.json`, TTL 24 h).
2. Cache miss: MediaWiki GeoSearch on pl.wikipedia.org (radius + 100 m margin, continuations followed so every page gets its intro extract). Areas (`city`, `adm*`, `region`, …, `dim ≥ 5000`) and pages without text are dropped.
3. Wikipedia down or timed out (8 s): expired cache entry, then `fixtures/pois-krakow.json`. The response says which one in `source` (`live` / `cache` / `fixture`). The endpoint never returns 5xx for an upstream failure.
4. `distanceM` is computed for the real position, filtered by `radius`, sorted, max 50.

The request log contains only method, path, status and time. Query strings carry the user's position and are never logged.

## For P4: using POIs in `/v1/segment`

```js
import { createApp } from './http/app.js';

createApp({
  poiService,
  health: { llm: async () => ({ ok, model }), tts: async () => ({ ok, provider }) },
  routes: [
    { method: 'POST', path: '/v1/segment', handler: async (req, res) => { /* readJson(req), sendJson(res, 200, segment) */ } },
    { method: 'GET', path: /^\/v1\/audio\/(?<id>[\w-]+)\.mp3$/, handler: async (req, res, { params }) => { /* params.id */ } },
  ],
});
```

- `poiService.get(id)`: any POI seen in a `/v1/pois` response or in the fixtures (no `distanceM`), or `null` (→ `404 unknown_poi`).
- `await poiService.deepSource(id)`: `{ text, sections: [{ title, text }], sourceUrl, partial }` for `DEEP_DIVE`. Full article without references, max ~8000 chars, cached 7 days. When Wikipedia is down it returns the summary with `partial: true`.
- `readJson`, `sendJson`, `HttpError` live in `src/http/http.js`. Throw `new HttpError(400, 'invalid_params', '...')` from a handler to get the contract error format.

## Configuration

See `.env.example`. Extra server-only variables: `HOST` (default `0.0.0.0`), `WIKI_API_URL`, `WIKI_TIMEOUT_MS` (8000), `POI_CACHE_TTL_MS` (24 h), `FIXTURE_POIS` (default `../fixtures/pois-krakow.json`).
