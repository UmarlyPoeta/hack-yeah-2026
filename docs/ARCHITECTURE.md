# Spacer z historią: architektura

> Przewodnik, który **idzie razem z tobą** i mówi prawdziwym polskim głosem. Wie, w którą stronę idziesz, co jest przed tobą i ile czasu zostało do następnego zabytku, więc płynnie łączy kolejne miejsca w jedną opowieść. Gdy się zatrzymasz, proponuje pogłębienie. Lokalizację dostaje **tylko po kliknięciu `LocationButton`**, bez stałego uprawnienia. Tekst pisze **Bielik** (polski open-source LLM) uruchomiony lokalnie w **Ollamie**, a czyta go **ElevenLabs**. Zapasowy głos offline to **Piper**.

- **Temat prowadzący:** Human-Centric Technology (doświadczenie kulturowe, odpowiedzialna technologia).
- **Drugi:** Intelligent Experiences (kontekstowy przewodnik: ruch, kierunek, tempo, zatrzymania).
- **Platforma w centrum:** HarmonyOS **Security Components** (`LocationButton`: autoryzacja tymczasowa, ważna do wygaszenia ekranu, przejścia w tło albo wyjścia z aplikacji), Location Kit, Media Kit (AVPlayer), Network Kit, ArkUI.
- **Suwerenność:** dane z polskiej Wikipedii (CC BY-SA), polski otwarty model (Bielik, SpeakLeash i ACK Cyfronet AGH) uruchomiony lokalnie, otwarty system.
- **Środowisko:** jeden emulator telefonu w DevEco Studio (compatible API 20, compile 23, target 24) z symulowanym GPS + laptop z `server/` i Ollamą.

## 1. Obraz całości

```
┌─────────────────────────────── TELEFON (ArkTS / ArkUI) ────────────────────────────────┐
│ UI (P5)        StartPage · WalkPage [pasek trasy + radar + teleprompter + odtwarzacz]   │
│                DeepDiveSheet · PrivacyPage · SettingsPage                               │
│                       ▲ stan (@ObservedV2)                                              │
│ VIEWMODEL      WalkViewModel (P2)  ── spina moduły, bez logiki decyzyjnej               │
│                       │                                                                 │
│ RDZEŃ (czysty, P2)    GuideDirector                                                     │
│                        ├ MotionTracker    pozycja wygładzona, prędkość, kurs, STOI/IDZIE│
│                        ├ Itinerary        POI przed tobą, kolejność, ETA, lewo/prawo    │
│                        ├ NarrationPlanner co i kiedy mówić + budżet długości            │
│                        └ Templates        tekst bez AI dla każdego typu segmentu        │
│ SESJA (P1)     WalkSession  IDLE/ACQUIRING/WALKING/PAUSED/ERROR                         │
│ ADAPTERY       LocationProvider ◀── LocationButton                                      │
│                 ├ LiveLocationProvider (geoLocationManager)             (P1)            │
│                 └ RouteReplayProvider  (tylko debug, oznaczony w UI)    (P1)            │
│                PoiRepository   ── GET /v1/pois    | fallback: rawfile fixtures   (P3)   │
│                SegmentService  ── POST /v1/segment | fallback: Templates; prefetch (P4) │
│                NarratorPlayer  ── AVPlayer (MP3 z audioUrl) | fallback: sam tekst  (P5) │
└───────────────────────────────────────────────┬───────────────────────────────────────┘
                                                │ HTTP JSON + MP3 (docs/CONTRACTS.md)
┌──────────────────────────── LAPTOP: server/ (Node 22) ──────▼───────────────────────────┐
│ GET  /v1/health                                                                          │
│ GET  /v1/pois       → Wikipedia GeoSearch (pl) → filtr obszarów → Poi[] → cache     (P3) │
│ POST /v1/segment    → źródła POI → prompt wg typu → LLM → walidator → TTS → Segment (P4) │
│ GET  /v1/audio/:id  → plik MP3 z cache                                              (P4) │
│ npm run warm        → pre-generacja tekstu i audio dla trasy demo                   (P4) │
│                                                                                          │
│ LlmProvider:  Ollama /api/chat (http://localhost:11434) + Bielik-4.5B-v3.0-Instruct GGUF │
│ TtsProvider:  ElevenLabs (domyślny, chmura, klucz w .env)  |  Piper pl_PL (offline)      │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

## 2. Przewodnik sekwencyjny

### 2.1 MotionTracker: z surowych fixów robi „jak idzie użytkownik”
- Odrzuca fixy z `accuracy > 50 m` i skoki niemożliwe dla pieszego (> 5 m/s).
- Prędkość: EMA z ~10 s. Kurs: azymut przemieszczenia na ostatnich ≥ 15 m (pojedynczy fix za bardzo szumi).
- Stan ruchu z histerezą: `STOPPED`, gdy prędkość < 0,3 m/s przez ≥ 8 s; `MOVING`, gdy > 0,6 m/s.

### 2.2 Itinerary: co jest przed tobą
Dla każdego POI w promieniu 250 m, gdzie θ to kąt między kursem a kierunkiem do POI:
- `along = d·cos θ` (ile zostało do POI wzdłuż kierunku marszu), `cross = d·sin θ` (znak to lewo albo prawo),
- POI jest przed tobą, gdy `along > 0` i `|cross| ≤ 60 m`, albo zawsze, gdy `d < 40 m`,
- `upcoming` jest posortowane po `along`, a `ETA = along / max(prędkość, 0,8 m/s)`,
- `passed`: `along < −20 m`. `missed`: minięty bez przybycia (nigdy nie był < 35 m),
- „następny” zmienia się tylko po minięciu albo gdy inny POI ma ETA krótsze o > 15 s (ochrona przed szumem kursu).

### 2.3 NarrationPlanner: co powiedzieć, kiedy i jak długo
Narrator mówi **jeden segment naraz**. Czas trwania segmentu to **prawdziwa długość audio** (`durationMs`). Zanim audio jest gotowe, planner szacuje go z tempa ok. 2,5 słowa/s.

| Segment | Kiedy | Długość | Priorytet |
|---|---|---|---|
| `WELCOME` | start spaceru | 30–50 słów | 3 |
| `APPROACH` | ETA do następnego ≤ 30 s i narrator wolny | 1 zdanie: „Za ok. 40 m po prawej Brama Floriańska” | 3 |
| `ARRIVAL` | dystans < 35 m (wyjście > 50 m) | `clamp(ETA_do_kolejnego × 2,5 × 0,7, 40, 120)` słów | 4 |
| `BRIDGE` | po `ARRIVAL`, użytkownik rusza, ETA do następnego ≥ 25 s | `clamp(ETA × 2,5 × 0,6, 20, 70)`: **łączy** poprzednie i następne miejsce wspólnym wątkiem | 2 |
| `DEEP_DIVE_OFFER` | `STOPPED` przy POI ≥ 8 s po `ARRIVAL` | przycisk „Opowiedz więcej o …” | 3 |
| `DEEP_DIVE` | po akceptacji | 200–350 słów, sekcje wg zainteresowań | 4 |
| `MISSED` | minięty POI, narrator wolny | 1 zdanie: „Po lewej minęliśmy …” | 1 |

- **Nie przerywamy w pół zdania.** Wyższy priorytet czeka na koniec bieżącego zdania.
- **Segmenty się przeterminowują:** `APPROACH` do minionego POI wypada z kolejki.
- **Dwa zabytki blisko siebie:** `ARRIVAL` pierwszego dostaje krótki budżet, `BRIDGE` jest pomijany, a `APPROACH` drugiego zaczyna się od „Tuż obok…”.
- **Prefetch:** gdy zmienia się `upcoming[0]`, planner zleca `ARRIVAL(next)` i `BRIDGE(current→next)` z **deadline = ETA**. Jeśli AI albo TTS nie zdąży, używa szablonu (tekst bez głosu albo z Piperem).

`GuideDirector` to czysta funkcja `step(stan, wejście, tNow) → (stan, akcje[])`. Test: odtworzenie `fixtures/demo-route-krakow.json` i sprawdzenie sekwencji segmentów.

## 3. AI i głos (serwer)

- **LLM:** Ollama + **Bielik-4.5B-v3.0-Instruct** (GGUF, Q4, ok. 3 GB RAM). `POST /api/chat` z `format` = JSON Schema segmentu, `stream: false`, `keep_alive: "30m"`. Model wybiera `LLM_MODEL` w `.env`.
- **Ugruntowanie:** prompt dostaje wyłącznie tekst źródłowy POI (streszczenia, a dla `DEEP_DIVE` pełniejszy artykuł, przycięty). Każde twierdzenie ma dosłowny cytat. Walidator odrzuca cytaty spoza źródła i liczby/lata spoza źródła. Po odrzuceniu następuje 1 retry, potem szablon.
- **TTS:** `TtsProvider` z dwiema implementacjami:
  - `elevenlabs` (domyślny): REST text-to-speech, model wielojęzyczny, wynik w MP3. Klucz `ELEVENLABS_API_KEY` i `ELEVENLABS_VOICE_ID` tylko w `server/.env`.
  - `piper` (offline): głos `pl_PL-gosia-medium` (albo `darkman`/`mc_speech`), wynik w WAV, konwersja do MP3 przez ffmpeg (AVPlayer obsługuje MP3/M4A, nie surowy PCM).
- **Cache:** tekst i audio po kluczu `(typ, poiId, fromPoiId, zainteresowania, budżet, wersja promptu, głos)`. `npm run warm` wypełnia cache dla trasy demo, co oszczędza limit znaków ElevenLabs i czas Bielika.
- **Prywatność:** do ElevenLabs trafia wyłącznie wygenerowany tekst o zabytku, bez lokalizacji i bez danych użytkownika. Serwer nie loguje pozycji, a `/v1/segment` przyjmuje tylko identyfikatory POI.
- **Model na telefonie** (MindSpore Lite / llama.cpp przez NDK) to kierunek rozwoju opisany w pitchu. Na emulatorze x86 w 20 h jest nierealny.

## 4. Zasady

1. **Działa bez serwera.** Aplikacja ma w `rawfile` dane POI i trasy oraz szablony dla każdego typu segmentu. Serwer, AI i głos wzbogacają aplikację, ale reprodukcja od nich nie zależy.
2. **Zero stałych uprawnień do lokalizacji.** Jedyna droga to `LocationButton`. Utrata autoryzacji to stan `PAUSED`, nie błąd. Manifest ma tylko `INTERNET` (system_grant).
3. **Czysty rdzeń, czas jako parametr:** testy Hypium są deterministyczne.
4. **Każde źródło za interfejsem**, z wersją live i zastępczą.
5. **Przejrzystość w UI:** etykieta „AI: Bielik (lokalnie) · głos: ElevenLabs” albo „szablon”, plus link do źródła.

## 5. `WalkSession`

```
IDLE ──tap LocationButton──▶ ACQUIRING ──pierwszy fix──▶ WALKING
  ▲                              │ timeout 15 s              │ onBackground / ekran off / błąd uprawnień
  │                              ▼                           ▼
  └──────── stop ────────── ERROR(NO_FIX|DENIED) ◀──── PAUSED ──tap LocationButton──▶ ACQUIRING
```
W `PAUSED` odtwarzanie narracji się zatrzymuje, a subskrypcja lokalizacji jest zdejmowana.

## 6. Struktura repozytorium

```
AppScope/, entry/, build-profile.json5, hvigorfile.ts, oh-package.json5   ← projekt DevEco (Hackathon Template)
entry/src/main/ets/
  model/      Poi.ets, Segment.ets, GeoPoint.ets
  guide/      geo.ets, MotionTracker.ets, Itinerary.ets, NarrationPlanner.ets, Templates.ets, GuideDirector.ets
  session/    WalkSession.ets
  location/   LocationProvider.ets, LiveLocationProvider.ets, RouteReplayProvider.ets
  data/       ApiConfig.ets, PoiRepository.ets, SegmentService.ets
  audio/      NarratorPlayer.ets
  viewmodel/  WalkViewModel.ets
  pages/      StartPage, WalkPage, PrivacyPage, SettingsPage
  components/ RouteStrip.ets, Radar.ets, Teleprompter.ets, DeepDiveSheet.ets, SessionBadge.ets
entry/src/main/resources/rawfile/  pois-krakow.json, demo-route-krakow.json
entry/src/test/                    testy Hypium
server/   src/{http,pois,segment,llm,tts,validate,cache}/, test/, eval/, scripts/warm.js, .env.example
fixtures/ tools/ docs/ AI_WORKFLOW.md README.md
```

## 7. Ryzyka

| Ryzyko | Zabezpieczenie | Kto |
|---|---|---|
| `LocationButton` nie współpracuje z symulowanym GPS albo wymaga deklaracji | spike w 1. godzinie; plan B: `requestPermissionsFromUser` z „tylko tym razem” | P1 |
| Emulator nie odtwarza trasy GPS | punkty ręcznie w panelu emulatora; `RouteReplayProvider` w debug, oznaczony | P1 |
| Emulator nie widzi serwera (sieć, HTTP bez TLS) | aplikacja działa offline; spike sieci w 1. godzinie | P1, P3 |
| Emulator nie wydaje dźwięku | spike; plan B: głos nagrany na fizycznym telefonie od mentorów, na emulatorze napisy | P5 |
| Bielik za wolny na CPU | prefetch z deadline, `npm run warm`, mniejsza kwantyzacja, szablony | P4 |
| Bielik źle trzyma JSON albo halucynuje | `format` = JSON Schema, walidator, retry, szablon | P4 |
| Limit znaków / awaria ElevenLabs | cache audio, warm, fallback do Pipera, a potem do samego tekstu | P4 |
| Wikidata SPARQL ma awarię (1 zapytanie/min) | używamy MediaWiki GeoSearch API Wikipedii | P3 |
| Klucz ElevenLabs w repo | tylko `server/.env` (ignorowany), `.env.example` bez wartości, audyt przed release | P1 |
