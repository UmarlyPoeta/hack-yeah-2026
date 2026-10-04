# server/

Backend for Spacer z historią. Node ≥ 22.9, no dependencies (`node:http`, `node --test`). API contract: [`docs/CONTRACTS.md`](../docs/CONTRACTS.md).

```sh
cd server
cp .env.example .env     # optional; defaults work without it
npm start                # prints localhost and LAN addresses for the emulator
npm test                 # offline: Wikipedia responses are replayed from test/fixtures/
npm run record-fixtures  # re-record test/fixtures/ (Wikipedia + Wikidata) from the live APIs (needs internet)
npm run warm -- --dry-run   # plan of the demo-route warm-up (see "Voice" below)
npm run tts-smoke        # ElevenLabs + Piper smoke test (add `voices` to list Polish voices)
```

## Endpoints

| Route | Status | Owner |
|---|---|---|
| `GET /v1/health` | done (`llm`/`tts` from config + last call; never wakes Modal or calls ElevenLabs) | P3, P4 |
| `GET /v1/pois?lat=&lon=&radius=` | done | P3 |
| `POST /v1/segment` | done: text (#18) + voice (#19) | P4 |
| `GET /v1/audio/<audioId>.mp3` | done (#19) | P4 |

## `/v1/pois` data flow

1. The position is snapped to a ~150 m grid cell. One cache entry serves the whole cell (`.cache/pois-areas.json`, TTL 24 h).
2. Cache miss, two searches around the cell centre (#40):
   - near: MediaWiki GeoSearch, 150 m, the nearest 50 pages with intro text (continuations followed);
   - wide: 600 m, page ids only, then language links; only places with `importance ≥ 0.6` get their details fetched.
   Areas (`city`, `adm*`, `region`, …, `dim ≥ 5000`) and pages without text are dropped.
3. Signals for every POI (`src/pois/signals.js`, rules in `src/pois/poi-rules.json`, shared with `tools/gen_fixtures.py`):
   - `importance` = log(1 + language versions) / log(41), clipped to 1;
   - `role` = `area` for streets, squares, the old town, districts, parks, city walls (Wikidata P31), else `sight`; parishes, dioceses and organisations without a building are dropped;
   - `partOfId` = Wikidata P361 ("part of") when the parent is in the same response.
   Wikidata down: role from Polish name prefixes, `partOfId: null`, warning `wikidata_unavailable`. Language links down: importance from summary length, warning `importance_fallback`. A result with a warning is served but not cached as fresh.
4. Wikipedia down or timed out (8 s): expired cache entry, then `fixtures/pois-krakow.json`. The response says which one in `source` (`live` / `cache` / `fixture`). The endpoint never returns 5xx for an upstream failure.
5. `distanceM` is computed for the real position, filtered by `radius`, sorted, max 50.

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

## Voice: TTS, `/v1/audio`, `npm run warm` (#19)

- `TTS_PROVIDER=elevenlabs`: ElevenLabs (`eleven_multilingual_v2`, `language_code: pl`), on error Piper (`tts_fallback_piper`). `piper`: Piper only. `none`: no audio. Piper writes WAV, ffmpeg turns it into MP3 (AVPlayer does not play raw PCM).
- **Template segments are voiced by Piper only** (`TTS_CLOUD_FOR_TEMPLATES=false`): ElevenLabs characters go to AI text. Free plan: 10 000 characters/month ≈ 15–20 `ARRIVAL`s.
- ElevenLabs 401/402/429 (quota, key, plan) switches it off for 10 min, Piper takes over without retrying ElevenLabs on every request. Only the generated text about the place is sent to ElevenLabs.
- Audio: `.cache/audio/<audioId>.mp3`, `audioId` = hash(voice, text), so the same text is never paid for twice; the text cache and the audio cache are separate (a TTS outage never costs another LLM call). `durationMs` is read from the MP3 frames (`src/tts/mp3.js`, within ~80 ms of ffprobe).
- `npm run warm -- [--limit 5] [--interests historia] [--no-voice] [--dry-run]`: walks `fixtures/demo-route-krakow.json`, picks POIs within 35 m in walking order and generates `WELCOME`, `ARRIVAL` and `BRIDGE` with the planner's budgets (ARCHITECTURE §2.3), bucketed to multiples of 10. LLM timeout 180 s (wakes Modal). The default `--limit 5` keeps ElevenLabs at ~4–5k characters; the whole route (32 segments) would be ~14k, over the free plan. **The app hits these entries only with the same `interests` and `maxWords` bucket.** Measured: 2 stops, Piper, 4/4 `ai` with audio.

Piper on Windows: `piper_windows_amd64.zip` from github.com/rhasspy/piper/releases into e.g. `%LOCALAPPDATA%\piper` (`PIPER_BIN` = full path to `piper.exe`), voice `pl_PL-gosia-medium.onnx` + `.onnx.json` from huggingface.co/rhasspy/piper-voices into `server/voices/`, ffmpeg via `winget install Gyan.FFmpeg`.

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
