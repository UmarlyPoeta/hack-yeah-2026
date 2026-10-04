# Spacer z historią: architektura

> Przewodnik, który **idzie razem z tobą** i mówi prawdziwym polskim głosem. Wie, w którą stronę idziesz, co jest przed tobą i ile czasu zostało do następnego zabytku, więc płynnie łączy kolejne miejsca w jedną opowieść. Gdy się zatrzymasz, proponuje pogłębienie. Lokalizację dostaje **tylko na czas jednego spaceru** (systemowa zgoda „Allow this time only”), bez lokalizacji w tle. Tekst pisze **Bielik** (polski open-source LLM) serwowany przez **Ollamę** na GPU w **Modal**, a czyta go **ElevenLabs**. Zapasowy głos offline to **Piper**.

- **Temat prowadzący:** Human-Centric Technology (doświadczenie kulturowe, odpowiedzialna technologia).
- **Drugi:** Intelligent Experiences (kontekstowy przewodnik: ruch, kierunek, tempo, zatrzymania).
- **Platforma w centrum:** jeden HAP na telefon i zegarek, jednorazowa zgoda na lokalizację (Location Kit), AVSession, Live View (telefon), wibracje zegarka, Distributed Data Object / kontynuacja (prawdziwe urządzenia), Media Kit, Network Kit, ArkUI. `LocationButton` nie istnieje w publicznym SDK HarmonyOS 6.1.1 (spike, #48).
- **Suwerenność:** dane z polskiej Wikipedii (CC BY-SA), polski otwarty model (Bielik, SpeakLeash i ACK Cyfronet AGH) na własnym wdrożeniu (Modal, bez zewnętrznego API LLM), otwarty system.
- **Środowisko:** jeden emulator telefonu w DevEco Studio (compatible API 20, compile 23, target 24) z symulowanym GPS + laptop z `server/`; Bielik w Ollamie na Modalu (`server/modal/`).

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
│ ADAPTERY       LocationProvider ◀── zgoda „Allow this time only”                         │
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
│ LlmProvider:  Ollama /api/chat na Modal (GPU, OLLAMA_URL) + Bielik-4.5B-v3.0-Instruct    │
│ TtsProvider:  ElevenLabs (domyślny, chmura, klucz w .env)  |  Piper pl_PL (offline)      │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

## 2. Przewodnik sekwencyjny

### 2.1 MotionTracker: z surowych fixów robi „jak idzie użytkownik”
- Odrzuca fixy z `accuracy > 50 m` i skoki niemożliwe dla pieszego (> 5 m/s).
- Prędkość: przemieszczenie netto w oknie ~10 s (sumowanie kroków kumuluje szum GPS). Kurs: azymut przemieszczenia na ostatnich ≥ 25 m (przy 15 m szum ±5 m daje wahania ±30°).
- Stan ruchu z histerezą: `STOPPED`, gdy prędkość < 0,3 m/s przez ≥ 8 s; `MOVING`, gdy > 0,6 m/s.

### 2.2 Itinerary: co jest przed tobą
Dla każdego POI w promieniu 250 m, gdzie θ to kąt między kursem a kierunkiem do POI:
- `along = d·cos θ` (ile zostało do POI wzdłuż kierunku marszu), `cross = d·sin θ` (znak to lewo albo prawo),
- POI jest przed tobą, gdy `along > 0` i `|cross| ≤ 60 m`, albo zawsze, gdy `d < 40 m`,
- `upcoming` jest posortowane po `along`, a `ETA = along / max(prędkość, 0,8 m/s)`,
- `passed`: `along < −20 m`; wraca do gry, gdy po zakręcie jest znów < 40 m i przed tobą (`along ≥ 0`). `missed`: minięty bez przybycia (nigdy nie był < 35 m),
- „następny” zmienia się tylko po minięciu, gdy inny POI ma ETA krótsze o > 15 s, albo gdy obecny cel wypadł z korytarza, a inny jest bliżej (ochrona przed szumem kursu i „przyklejeniem” do długich obiektów, np. murów).

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

- **Nie przerywamy w ogóle.** Segment zawsze kończy się w całości; kolejka z priorytetami czeka (`WELCOME` 5, `ARRIVAL`/`DEEP_DIVE` 4, `APPROACH` 3, `BRIDGE` 2, `MISSED` 1).
- **Czas liczony do startu opowieści,** nie do drzwi zabytku: `ARRIVAL` zaczyna się w promieniu 35 m, więc ETA, budżety słów i zapowiedzi liczą czas do tego momentu.
- **Segmenty się przeterminowują:** `APPROACH` do osiągniętego przystanku i `ARRIVAL` przystanku oddalonego o > 80 m wypadają z kolejki; `MISSED` żyje 60 s.
- **Prefetch:** gdy zmienia się następny główny przystanek, planner zleca `ARRIVAL(next)` z **deadline = czas do startu opowieści**; `BRIDGE(current→next)` zleca w chwili startu `ARRIVAL`. Gdy AI albo TTS nie zdąży, gra szablon.

### 2.4 Przystanki i wybór, o czym mówić (`Stops`)

Na trasie demo jest 77 miejsc, z czego 67 w zasięgu: kamienice, obszary, duplikaty. Przewodnik opowiada o **przystankach**, nie o każdym punkcie:
- **Grupowanie:** miejsca w promieniu 40 m od siebie oraz połączone przez `partOfId` tworzą jeden przystanek; główne jest to z najwyższym `importance`, reszta trafia do zdania „Obok: …”. Obszary (`role: area`) nigdy nie są przystankami.
- **Próg względny:** przystanek jest główny, gdy należy do górnych 30% ważności w promieniu 500 m, z dolnym minimum 0,15 i górnym limitem 0,6. Dzięki temu w Krakowie mówimy o najważniejszych, a w małym mieście też jest o czym mówić.
- **Tylko miejsca:** wpisy bez typu współrzędnych (`kind: null`) to w danych głównie wydarzenia i organizacje („Sonderaktion Krakau”, „Strajk w Sempericie”); nigdy nie są przystankiem ani nie padają w „Obok: …”.
- **Wypełniacze:** przystanek poniżej progu dostaje `ARRIVAL` tylko wtedy, gdy ma ważność ≥ 0,3, przewodnik milczał ≥ 30 s, do następnego głównego jest ≥ 90 s, i najwyżej raz na 3 minuty.
- **Spóźnione przybycie:** główny przystanek minięty bliżej niż 60 m albo wcześniej zapowiedziany dostaje `ARRIVAL` zamiast „już za nami”. `MISSED` tylko dla miejsc bliżej niż 120 m, najwyżej jedno na minutę.
- **Szablony** trzymają nazwy w mianowniku („Za nami: X, przed nami: Y”), bo bez modelu nie odmienimy poprawnie dowolnej nazwy.

Wynik na trasie demo (331 miejsc z #40): 16 przystanków w 19 minut, od Barbakanu po Zamek na Wawelu z Katedrą i Dzwon Zygmunt, segmenty nigdy się nie nakładają, kolejność zgodna z trasą także przy szumie GPS ±5–8 m.

### 2.5 Silnik w aplikacji

`GuideDirector.step(zdarzenie) → akcje[]` łączy `MotionTracker`, `Itinerary` i `NarrationPlanner`. Zdarzenia: `FIX`, `TICK` (co ~1 s), `SEGMENT_READY`, `PLAYBACK_FINISHED`, `DEEP_DIVE_ACCEPTED`. Akcje: `REQUEST_SEGMENT`, `PLAY_SEGMENT`, `OFFER_DEEP_DIVE`, `WITHDRAW_DEEP_DIVE`.
`WalkController` wykonuje akcje przez trzy porty: `SegmentClient` (adapter na `SegmentService` P3), `NarrationOutput` (adapter na `NarratorPlayer` P5), `Clock`. Wystawia `WalkUiState` z polami, których używa `WalkPage`. `WalkViewModel.ets` (`@ObservedV2`) tylko odbija ten stan do ArkUI i odpala tick. `GuideDebugPage` odtwarza trasę demo ×10 (oznaczona jako symulacja).

## 3. AI i głos (serwer)

- **LLM:** Ollama + **Bielik-4.5B-v3.0-Instruct** (GGUF Q8_0, ok. 5 GB VRAM) na GPU w Modal (`server/modal/`, endpoint z proxy auth: nagłówki `Modal-Key`/`Modal-Secret`). `POST /api/chat` z `format` = JSON Schema segmentu, `stream: false`, `keep_alive: "30m"`. Model wybiera `LLM_MODEL` w `.env`.
- **Ugruntowanie:** prompt dostaje wyłącznie tekst źródłowy POI (streszczenia, a dla `DEEP_DIVE` pełniejszy artykuł, przycięty). Każde twierdzenie ma dosłowny cytat. Walidator odrzuca cytaty spoza źródła i liczby/lata spoza źródła. Po odrzuceniu następuje 1 retry, potem szablon.
- **TTS:** `TtsProvider` z dwiema implementacjami:
  - `elevenlabs` (domyślny): REST text-to-speech, model wielojęzyczny, wynik w MP3. Klucz `ELEVENLABS_API_KEY` i `ELEVENLABS_VOICE_ID` tylko w `server/.env`.
  - `piper` (offline): głos `pl_PL-gosia-medium` (albo `darkman`/`mc_speech`), wynik w WAV, konwersja do MP3 przez ffmpeg (AVPlayer obsługuje MP3/M4A, nie surowy PCM).
- **Cache:** tekst i audio po kluczu `(typ, poiId, fromPoiId, zainteresowania, budżet, wersja promptu, głos)`. `npm run warm` wypełnia cache dla trasy demo, co oszczędza limit znaków ElevenLabs i czas Bielika.
- **Prywatność:** do ElevenLabs trafia wyłącznie wygenerowany tekst o zabytku, bez lokalizacji i bez danych użytkownika. Serwer nie loguje pozycji, a `/v1/segment` przyjmuje tylko identyfikatory POI.
- **Model na telefonie** (MindSpore Lite / llama.cpp przez NDK) to kierunek rozwoju opisany w pitchu. Na emulatorze x86 w 20 h jest nierealny.

## 4. Zasady

1. **Działa bez serwera.** Aplikacja ma w `rawfile` dane POI i trasy oraz szablony dla każdego typu segmentu. Serwer, AI i głos wzbogacają aplikację, ale reprodukcja od nich nie zależy.
2. **Lokalizacja tylko na ten spacer.** Zgoda „Allow this time only”; system trzyma ją, dopóki żyje proces aplikacji, i odbiera po jego zamknięciu. Lokalizację w tle wyłączamy sami: przejście w tło = `PAUSED` i zatrzymany dostawca. Wznowienie prosi system o zgodę; okienko pojawi się tylko wtedy, gdy zgoda wygasła. Żadnej lokalizacji w tle.
3. **Czysty rdzeń, czas jako parametr:** testy Hypium są deterministyczne.
4. **Każde źródło za interfejsem**, z wersją live i zastępczą.
5. **Przejrzystość w UI:** etykieta „AI: Bielik · głos: ElevenLabs” albo „szablon”, plus link do źródła.

## 5. `WalkSession` (#48)

```
IDLE ──start──▶ ASKING ──„Allow this time only”──▶ ACQUIRING ──pierwszy fix──▶ WALKING
                  │ odmowa                            │ 15 s bez fixu / lokalizacja wyłączona  │ tło, błąd lokalizacji,
                  ▼                                   ▼                                         ▼ pauza użytkownika
                ERROR(DENIED) ◀──────────────── ERROR(NO_FIX|LOCATION_OFF)                 PAUSED ──wznów──▶ ASKING
```
Lokalizacja (`LiveLocationProvider`, 1 Hz, scenariusz NAVIGATION) działa tylko w `ACQUIRING`/`WALKING`. `RouteReplayProvider` (trasa demo) jest oznaczony w UI jako SYMULACJA. Kod: `session/WalkSession.ets`, `location/*`, `platform/AppLifecycle.ets`.

## 5a. Dwa urządzenia: telefon + zegarek (#50)

Ten sam HAP (`deviceTypes: phone, wearable`). Każde urządzenie ma pełny silnik; łącze (`DeviceLink`) ustala role:
- **SOLO**: samo, bez łącza.
- **LEAD**: liczy, mówi, wysyła `state` (co pokazać) co zmianę i co ≤ 3 s.
- **FOLLOW**: silnik działa wyciszony (własna strzałka i odległość z własnego GPS), tekst i oferta pogłębienia przychodzą od LEAD-a; przyciski wysyłają `cmd`; wibracje (#52) liczone lokalnie.
- **Przejęcie („Przejmij”)**: FOLLOW wysyła `cmd: handoff` → LEAD wysyła `progress` (opowiedziane, zapowiedziane, ostatni przystanek), milknie i staje się FOLLOW → nowy LEAD importuje postęp i mówi dalej bez powtórek.
- Brak wiadomości przez 10 s → FOLLOW przechodzi w SOLO.
- Łącze nie przenosi pozycji, odległości ani kierunku (#56). Implementacje: `RelayLink` przez serwer (emulatory, #51), `DistributedLink` (prawdziwe urządzenia, #57).
Kod: `viewmodel/WalkController.ets`, `link/DeviceLink.ets`, `viewmodel/Haptics.ets`, `platform/VibratorHaptics.ets`, `platform/LiveViewPublisher.ets`.

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
| `LocationButton` nie istnieje w publicznym SDK 6.1.1 (potwierdzone w spike'u) | zgoda „Allow this time only” (`requestPermissionsFromUser`), sprawdzona na telefonie i zegarku | P1 |
| Emulator nie odtwarza trasy GPS | punkty ręcznie w panelu emulatora; `RouteReplayProvider` w debug, oznaczony | P1 |
| Emulator nie widzi serwera (sieć, HTTP bez TLS) | aplikacja działa offline; spike sieci w 1. godzinie | P1, P3 |
| Emulator nie wydaje dźwięku | spike; plan B: głos nagrany na fizycznym telefonie od mentorów, na emulatorze napisy | P5 |
| Bielik za wolny na CPU | prefetch z deadline, `npm run warm`, mniejsza kwantyzacja, szablony | P4 |
| Bielik źle trzyma JSON albo halucynuje | `format` = JSON Schema, walidator, retry, szablon | P4 |
| Limit znaków / awaria ElevenLabs | cache audio, warm, fallback do Pipera, a potem do samego tekstu | P4 |
| Wikidata SPARQL ma awarię (1 zapytanie/min) | używamy MediaWiki GeoSearch API Wikipedii | P3 |
| Klucz ElevenLabs w repo | tylko `server/.env` (ignorowany), `.env.example` bez wartości, audyt przed release | P1 |
