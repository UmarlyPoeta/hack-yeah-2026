# tour

A walking guide for HarmonyOS (API 20+) that finds landmarks around you and tells their story out loud, in Polish. The story is written by an LLM only from the Wikipedia article about the place, checked against that source, and read by ElevenLabs. HackYeah 2026, Huawei / OpenHarmony challenge.

Themes: **Human-Centric Technology** (hands-free mode for people who cannot look at a screen), **Intelligent Experiences** (grounded AI narration), **Spatial Experiences** (position-driven guide).

## What it does

- **First launch:** welcome, interests, location permission. From one location fix the app builds a queue of 8 nearby landmarks with photos. The queue is saved on the device, so the app is never empty, also offline.
- **Odkrywaj (Discover):** the nearest landmark, the next ones in the queue, and a card about the current town.
- **Place screen:** Wikipedia photos and the AI story load together behind a loading screen with facts. Texts for the whole queue are prepared in advance, so opening a place waits only for the voice (~5 s).
- **Mapa:** dark map with the queued and saved landmarks.
- **Moje:** saved places; hands-free mode; the server address; reset.
- **Hands-free mode** (off by default, switched on by someone for the user): within 60 m of a landmark the phone vibrates and the story starts by itself.

## HarmonyOS capabilities used

| Capability | Kit / API | Where |
| --- | --- | --- |
| Position for nearby landmarks | Location Kit (`geoLocationManager`), permission request via `abilityAccessCtrl` | `store/UserLocation.ets` |
| "Landmark nearby" notification, max 1 per 2 min; Start plays without opening the app; offered to paired watches (`distributedOption`) | Notification Kit, `WantAgent`, common events | `store/Notifier.ets`, `store/HandsFree.ets` |
| Guide keeps running in the background | Background Tasks Kit (continuous task: location, audio playback) | `store/Guide.ets` |
| Story on the lock screen and in the control centre | AVSession Kit | `audio/NarrationSession.ets` |
| Home-screen widget with the nearest landmark | Form Kit | `widget/*` |
| Audio playback | Media Kit (`AVPlayer`) | `audio/NarratorPlayer.ets` |
| Vibration on arrival | Sensor Service Kit (`vibrator`) | `store/HandsFree.ets` |
| Settings, queue and photos on the device | ArkData Preferences, Core File Kit | `store/*` |
| Map | ArkWeb (`Web` + `javaScriptProxy`), Leaflet in `rawfile/map/` | `components/map/MapView.ets` |

## Architecture

```
HarmonyOS app (Projekt/, ArkTS + ArkUI)           server (server/, Node 22, no dependencies)
  onboarding, tabs, place screen                    GET  /v1/pois     landmarks near a point (pl.wikipedia + Wikidata)
  store/: queue, saved, settings, guide loop  --->  POST /v1/segment  story about a place: LLM + grounding validator
  data/: PoiRepository, SegmentService        <---  GET  /v1/audio    MP3 from ElevenLabs (Piper as fallback)
```

- The LLM gets only the Wikipedia text of the place. The validator requires every number in the story to appear in the source and every claim to quote it; otherwise one retry, then a template from the source.
- The app never sends its route or the user's identity. Details: [`AI_WORKFLOW.md`](AI_WORKFLOW.md) (AI feature disclosure), [`docs/CONTRACTS.md`](docs/CONTRACTS.md) (API), [`server/README.md`](server/README.md).
- Without the server the app still works: bundled Kraków data (`rawfile/pois-krakow.json`) and the start of the Wikipedia summary instead of AI text, no voice.

## Requirements

- DevEco Studio 6.1 or later (HarmonyOS SDK 6.1.1, API 24; minimum API 20), with the phone emulator
- Node.js 22.9 or later
- An Anthropic API key, an ElevenLabs API key and voice ID (for AI text and voice)

## 1. Start the server

```sh
cd server
cp .env.example .env      # Windows: copy .env.example .env
```

Fill in `server/.env`: `ANTHROPIC_API_KEY`, `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID`. Claude (`LLM_PROVIDER=claude`) is the default. Then:

```sh
npm test      # 100 offline tests
npm start     # port 8787
```

Check `http://localhost:8787/v1/health`: it should show `"ok":true`, `"model":"claude-haiku-4-5-20251001"` and `"provider":"elevenlabs"`. Step-by-step for Windows and Linux: [`docs/RUN_SERVER.md`](docs/RUN_SERVER.md).

## 2. Build and run the app

```sh
cd Projekt
devecocli build                        # entry/build/default/outputs/default/entry-default-unsigned.hap
devecocli run                          # install and start on the running emulator
```

Or open `Projekt/` in DevEco Studio and press Run. The app connects to `http://10.0.2.2:8787`, which is the computer running the emulator, so with the server from step 1 nothing needs to be typed. Check in the app: **Moje → Ustawienia → Serwer** shows "Połączono z serwerem".

**A real phone** cannot reach `10.0.2.2`:
1. Sign the app: `devecocli auth login`, connect the phone (developer mode, USB debugging), `devecocli signature generate`, then `devecocli run --device <name>`. Never commit the generated signing files.
2. Make the server reachable, e.g. `cloudflared tunnel --url http://localhost:8787`, and type the printed `https://…trycloudflare.com` address in **Moje → Serwer**.

## Emulator notes (simulated parts)

- If the emulator's location is off, the app uses a fixed point at the Main Market Square in Kraków and says so during onboarding. Set the emulator location (Location panel) near a landmark to test hands-free mode.
- A paired watch cannot be emulated; the notification is marked for wearables, but this was not verified on a real watch.

## Tests

- Server: `cd server && npm test`.
- App unit tests (Hypium, local): see [`docs/TESTING.md`](docs/TESTING.md).

## Data and licences

Landmark texts and photos: Polish Wikipedia and Wikimedia Commons (CC BY-SA 4.0). Town lookup: OpenStreetMap Nominatim. Map tiles: Esri, HERE, Garmin, © OpenStreetMap contributors. Fonts: Manrope (SIL OFL). Map library: Leaflet (BSD-2-Clause).
