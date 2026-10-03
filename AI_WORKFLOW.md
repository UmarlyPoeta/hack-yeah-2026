# AI Workflow

This project uses AI-assisted development and ships an AI feature. Keep this document current and public-safe: no credentials, tokens, personal data, private endpoints or confidential prompts.

## Tools used

| Model, agent, MCP server, or Agent Skill | Version or source | Role in the project |
| --- | --- | --- |
| Claude Code (CLI) with Claude Opus 5.5 (`claude-opus-5-5`) | Claude Code 2.1.288 | ideation, research of platform APIs, architecture, task breakdown into GitHub issues, fixture generator |
| Bielik-4.5B-v3.0-Instruct (SpeakLeash / ACK Cyfronet AGH) via Ollama | GGUF, Hugging Face `speakleash` | product feature: self-hosted LLM (Ollama on Modal GPU) writing grounded tour-guide narration (`POST /v1/segment`) |
| ElevenLabs text-to-speech | REST API, multilingual model | product feature: Polish voice of the guide |
| Piper TTS (`pl_PL` voices) | rhasspy/piper | product feature: offline fallback voice |

## Important prompts and instructions

- Hackathon template `AGENTS.md`: repository-wide constraints.
- Ideation (summary): "scan the challenge repo and prepare a 5-person team"; the team then iterated on ideas. Gaze-scroll + OLED ring light was abandoned (camera unavailable in the emulator, too much hardware risk), as were several alternatives, before choosing a location-based storytelling app built around HarmonyOS Security Components.
- Planning (summary): "decided on 'Spacer z historią', no permanent permissions, everything emulated on one phone; create GitHub issues for 5 people, architecture, testing, integration via PRs". Follow-ups: "use a local model, not a cloud API key", "the guide must be sequential and real-time, with smooth transitions between consecutive sights and a deep dive when the user stops", "real Polish voice: Bielik + ElevenLabs".

## AI-assisted work log

| Date | Tool/model | Request or task | Generated or changed | Human review and validation |
| --- | --- | --- | --- | --- |
| 2026-10-03 | Claude Code / Opus 5.5 | Research `LocationButton` semantics, data sources, emulator limits | `docs/ARCHITECTURE.md`, `docs/CONTRACTS.md`, `docs/TESTING.md`, `docs/TEAM.md` | Claims checked against OpenHarmony docs; open questions marked as spikes in issues |
| 2026-10-03 | Claude Code / Opus 5.5 | Sequential guide design, local LLM + TTS choice, backlog of 32 issues for 5 roles | `docs/*` (rewrite), `docs/ROLES.md`, `tools/issues.md`, `tools/create_issues.py`, `server/.env.example` | Script dry-run validated references/labels; Piper Polish voices, Bielik GGUF, Ollama JSON schema and AVPlayer MP3 support checked in public docs; Core Speech Kit found to lack Polish |
| 2026-10-03 | Claude Code / Opus 5.5 | Server skeleton, `/v1/health`, `/v1/pois` (GeoSearch, filter, grid cache, fallbacks), deep-dive source text | `server/src/**`, `server/test/**`, `server/scripts/record-wiki-fixtures.js`, `server/README.md` | 38 offline `node --test` tests on recorded Wikipedia responses; manual smoke test against live pl.wikipedia.org |
| 2026-10-03 | Claude Code / Opus 5.5 | App data layer: `PoiRepository` (HTTP + rawfile fallback, refetch after 150 m), `SegmentService` (deadline, local template, late upgrade, prefetch, max parallel requests), contract models | `Projekt/entry/src/main/ets/{model,data}/*`, `Projekt/entry/src/test/data/*` | `devecocli check arkts` clean, `devecocli build` OK, 17 Hypium local unit tests with fake HTTP pass (suite execution confirmed with a deliberate failing canary); not yet run on the emulator against the real server |
| 2026-10-03 | Claude Code / Opus 5.5 | Visual redesign of the app UI ("printed museum guide" look) | `Projekt/entry/src/main/ets/{common,components,pages}/*`, bundled Newsreader font (OFL) in `rawfile/fonts/` | Each screen checked on the DevEco emulator (Pura 90, API 20) with screenshots; `check arkts` clean, unit tests pass; screen data is still mock until the guide engine is wired |
| 2026-10-03 | Claude Code / Opus 5.5 | P2 guide engine: MotionTracker, Itinerary, Stops, Templates, NarrationPlanner, GuideDirector, WalkController/WalkViewModel, debug replay page | `guide-lab/` (TS + Node tests), `Projekt/entry/src/main/ets/{guide,viewmodel,model,data,pages}`, Hypium tests, `docs/ARCHITECTURE.md` §2 | Every module first run on the real demo route and printed as a walk script, rules adjusted on what the data showed (heading baseline, passing at corners, area POIs, Polish case endings); 54 Node tests incl. GPS-noise runs, 33 Hypium tests and the HAP build run in DevEco via hvigor; reviewed by P2 |
| 2026-10-03 | Claude Code / Opus 5.5 | Generate real demo data | `tools/gen_fixtures.py`, `fixtures/*` | Script run against live Wikipedia API; output inspected (77 POIs, 1.46 km route) |
| 2026-10-03 | Claude Code / Opus 5.5 | Host Bielik on Modal instead of a local Ollama (#6) | `server/modal/bielik_ollama.py`, `server/modal/smoke_test.py`, `server/modal/README.md`, `server/.env.example`, docs | Model files and chat template checked on the Hugging Face model card; Modal API signatures checked in the installed SDK; deploy + smoke test results to be added to #6 |
| 2026-10-03 | Claude Code / Opus 5.5 | ElevenLabs + Piper spike (#7) | `server/scripts/tts-smoke.js`, `server/.env.example` | Ran against the live ElevenLabs API (plan, Polish voices, MP3) and local Piper `pl_PL-gosia-medium` + ffmpeg; samples listened to by a human; found that free plan blocks library voices via API (HTTP 402) |

## Workflow

### Ideation and architecture
The AI checked each candidate idea against the DevEco emulator capability table and the judging criteria. Ideas needing camera, Bluetooth or distributed features were rejected. Platform claims (e.g. `LocationButton` temporary authorization lasting until background/screen-off) were verified in the OpenHarmony documentation before being used.

### Implementation
_To be filled per PR._

### Testing and debugging
_To be filled per PR._

## Unsuccessful approaches

- Wikidata SPARQL (`query.wikidata.org`) as the live POI source: during the event it was rate-limited to 1 request/minute because of an outage. Switched to the MediaWiki GeoSearch API of pl.wikipedia.org.

## Known limitations

_To be filled._

## AI feature disclosure

- Model or service: **Bielik-4.5B-v3.0-Instruct** (Polish open-source LLM by SpeakLeash and ACK Cyfronet AGH), GGUF Q8_0, served by Ollama on our own **Modal** GPU deployment (`server/modal/`), not a third-party LLM API. Voice: **ElevenLabs** text-to-speech (cloud); offline fallback **Piper** with a `pl_PL` voice.
- Inference flow: the app sends only a segment request (kind, place id(s), interests, word budget) to our server. The server loads the Wikipedia source text of the place(s), builds a prompt per segment kind, calls Ollama `/api/chat` on Modal with a JSON Schema `format`, validates the result, then synthesises audio and returns text + MP3 URL.
- Data handling and privacy: the user's location stays on the phone, apart from a coarse `/v1/pois` query to our own server, which does not log positions. LLM inference is local. Only the generated text about a public monument is sent to ElevenLabs, with no location and no user data. The ElevenLabs key lives only in `server/.env`.
- Failure and fallback behavior: a grounding validator rejects claims whose quotes are not in the source and numbers/years absent from the source; one retry, then a template built from the source. TTS chain ElevenLabs -> Piper -> text only. The app keeps working fully offline with bundled data and templates. The UI labels every segment (AI/template, voice) and links the source (CC BY-SA).
- Evaluation: `server/eval/` (issue AI-EVAL): first-pass validation rate, generation latency, manual 1-5 rating.
