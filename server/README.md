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
| `GET /v1/health` | done (`llm` from config + last LLM call, never wakes Modal; `tts` `ok: false` until #19) | P3, P4 |
| `GET /v1/pois?lat=&lon=&radius=` | done | P3 |
| `POST /v1/segment` | done, text only (#18); `audioUrl: null` + `tts_unavailable` until #19 | P4 |
| `GET /v1/audio/:id.mp3` | todo (#19) | P4 |

## `/v1/pois` data flow

1. The position is snapped to a ~100 m grid cell. One cache entry serves the whole cell (`.cache/pois-areas.json`, TTL 24 h).
2. Cache miss: MediaWiki GeoSearch on pl.wikipedia.org (radius + 100 m margin, continuations followed so every page gets its intro extract). Areas (`city`, `adm*`, `region`, …, `dim ≥ 5000`) and pages without text are dropped.
3. Wikipedia down or timed out (8 s): expired cache entry, then `fixtures/pois-krakow.json`. The response says which one in `source` (`live` / `cache` / `fixture`). The endpoint never returns 5xx for an upstream failure.
4. `distanceM` is computed for the real position, filtered by `radius`, sorted, max 50.

The request log contains only method, path, status and time. Query strings carry the user's position and are never logged.

## `/v1/segment` data flow (#18)

1. Request checked (`kind`, `poiId`, `fromPoiId` for `BRIDGE`, `interests`, `maxWords` 5–400, `voice`). Unknown fields are ignored; the client never sends source text (prompt-injection guard). Unknown POI → `404 unknown_poi`.
2. `APPROACH` / `MISSED`: template right away, no LLM. The server never sees the position, so they use the forms without distance and side.
3. Source text: the POI `summary`; the article text (`poiService.deepSource`) for `DEEP_DIVE` and for summaries under 600 chars (Barbakan has 198), so the model does not fill gaps itself. `BRIDGE` gets both places.
4. Bielik on Modal (`src/llm/OllamaClient.js`): Ollama `/api/chat`, `format` = JSON Schema `{title?, text, claims[{text, quote}]}`, `num_predict` from `maxWords`, headers `Modal-Key` / `Modal-Secret`. Timeouts `LLM_TIMEOUT_MS` 45 s, `LLM_DEEP_DIVE_TIMEOUT_MS` 90 s.
5. Validator (`src/validate/grounding.js`): every number in the text must be in the source (strict); a claim's quote must match a source passage on ≥ 80 % of its words in order; bad claims are dropped, the segment fails when more claims are bad than good. Markdown and list numbers are stripped from the text.
6. Failure → 1 retry with the list of problems (`validation_retry`); a quick HTTP 5xx from Ollama → 1 retry (`llm_retry`); then the template with `validation_failed` / `llm_timeout` / `llm_unavailable`. Timeouts are not retried (the app's deadline would pass anyway).
7. AI segments are cached in `.cache/segments.json` (30 days) by `kind|poiId|fromPoiId|interests|maxWords|PROMPT_VERSION|model`; `id` is a hash of that key. Templates are not cached, so the LLM is tried again after an outage. Identical concurrent requests share one LLM call.

Measured on Bielik Q8_0, T4, warm (6 requests on the demo route): all `origin: ai` on the first attempt, 6–14 s each (`DEEP_DIVE` 14 s). After > 2 min idle the Modal container is cold: the first request needs ~90 s and ends as a template (`llm_timeout`), so the app should wake the model at walk start. Known limits: the validator cannot catch wrong words without numbers (e.g. „sklep galaretowy” for „galanteryjny”) or Roman-numeral centuries.

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
