# Backlog: Spacer z historią

Plik czytany przez `tools/create_issues.py`. Każda sekcja `## [ID] Tytuł` to jedno issue.
Linie `labels:`, `milestone:`, `depends:` to metadane. Reszta to treść. `{{ID}}` zamienia się na `#numer`.

## [SCAFFOLD] Projekt DevEco z Hackathon Template + struktura katalogów
labels: owner:P1, area:app, type:feature, prio:P0
milestone: M0 Fundament
depends:

**Cel:** projekt, który buduje się i startuje na emulatorze. Odblokowuje wszystkich, którzy piszą ArkTS.

- [ ] Create Project → **Hackathon Template**, Phone, Compatible SDK **6.0.0 (API 20)**; w `build-profile.json5`: compile **23**, target **24**
- [ ] katalogi z `docs/ARCHITECTURE.md` §6 (`model/ guide/ session/ location/ data/ audio/ viewmodel/ pages/ components/`) z pustymi plikami-zaślepkami
- [ ] skopiuj `fixtures/pois-krakow.json` i `fixtures/demo-route-krakow.json` do `entry/src/main/resources/rawfile/`
- [ ] `module.json5`: tylko `ohos.permission.INTERNET`
- [ ] pusty test Hypium przechodzi lokalnie
- [ ] `.gitignore` z repo zostaje (nie commitujemy `build/`, `oh_modules/`, `.p12`)

**Gotowe gdy:** `main` buduje się w DevEco i startuje na emulatorze z ekranem „Spacer z historią”.

## [SPIKE-LOC] Spike: LocationButton + GPS na emulatorze
labels: owner:P1, area:app, type:spike, prio:P0
milestone: M0 Fundament
depends: SCAFFOLD

**Cel:** potwierdzić fundament projektu. Timebox **45 min**. Wynik opisz w komentarzu w tym issue.

Pytania do rozstrzygnięcia:
1. Czy `LocationButton` wymaga deklaracji uprawnienia lokalizacji w `module.json5`?
2. Czy po kliknięciu `geoLocationManager.on('locationChange', ...)` dostaje pozycję ustawioną w panelu lokalizacji emulatora?
3. Czy emulator potrafi odtworzyć trasę (GPX / sekwencja punktów)? Jeśli nie, potrzebny jest `RouteReplayProvider` ({{LOCATION}}).
4. Co dokładnie dzieje się po wyjściu do ekranu głównego i powrocie (błąd? brak eventów?).

**Plan B**, jeśli `LocationButton` nie działa: `abilityAccessCtrl.requestPermissionsFromUser` z `APPROXIMATELY_LOCATION` i opcją „tylko tym razem”. Zgłoś to zespołowi, bo zmienia pitch.

Źródło: OpenHarmony docs „Using LocationButton” (autoryzacja tymczasowa do wygaszenia ekranu / tła / wyjścia).

## [SPIKE-NET] Spike: emulator → serwer na laptopie
labels: owner:P1, area:app, type:spike, prio:P0
milestone: M0 Fundament
depends: SCAFFOLD, SERVER-SKEL

Timebox **30 min**. Z emulatora wywołaj `GET http://<IP-laptopa-w-LAN>:8787/v1/health` przez `@kit.NetworkKit` http.

- [ ] działa z IP laptopa? (`localhost` w emulatorze to sam emulator)
- [ ] czy HTTP bez TLS jest blokowany? Jeśli tak, jaka konfiguracja go odblokowuje (dokładny klucz dla API 20+)?
- [ ] firewall: Windows (zezwól Node w sieci prywatnej), Fedora (`sudo firewall-cmd --add-port=8787/tcp`)

Wynik wpisz do komentarza i do `docs/` (sekcja w README robi {{README}}).

## [SPIKE-AUDIO] Spike: odtwarzanie MP3 przez AVPlayer na emulatorze
labels: owner:P5, area:app, type:spike, prio:P0
milestone: M0 Fundament
depends: SCAFFOLD

Timebox **30 min**. Dowolny krótki MP3 w `rawfile`, odtworzony przez `media.createAVPlayer()`.

- [ ] słychać dźwięk na głośnikach laptopa?
- [ ] działa też z URL `http://<IP>:8787/...` (strumień z serwera)?

Jeśli emulator nie wydaje dźwięku: demo głosu nagrywamy na fizycznym telefonie od mentorów, a na emulatorze zostaje teleprompter. Zgłoś od razu.

## [SERVER-SKEL] Szkielet server/ (Node 22)
labels: owner:P3, area:server, type:feature, prio:P0
milestone: M0 Fundament
depends:

- [ ] `server/package.json` (Node ≥ 22, `"type": "module"`), skrypty `start`, `test`, `warm`
- [ ] `node:http` (bez frameworka), router `/v1/*`, JSON errors wg `docs/CONTRACTS.md`
- [ ] config z `server/.env` (wzór `server/.env.example`, prosty parser albo `node --env-file`)
- [ ] `GET /v1/health` (na razie `llm.ok`/`tts.ok` = false)
- [ ] `node --test` z jednym testem health
- [ ] log startu wypisuje adresy LAN (przyda się do {{SPIKE-NET}})

## [LLM-SETUP] Ollama + Bielik: instalacja i pomiar
labels: owner:P4, area:ai, type:spike, prio:P0
milestone: M0 Fundament
depends:

- [ ] Ollama na laptopie-serwerze, model **Bielik-4.5B-v3.0-Instruct** (GGUF `speakleash`, kwantyzacja Q4). Zapisz dokładną komendę instalacji (np. `ollama pull hf.co/...` albo `ollama create` z Modelfile) do `server/README.md`
- [ ] test `/api/chat` z `format` = mały JSON Schema: czy Bielik trzyma schemat?
- [ ] **pomiar:** czas generacji ~100 słów po polsku (cold i warm, `keep_alive`). Wpisz liczby tutaj, bo od nich zależy prefetch w {{SEGMENT-SERVICE}}
- [ ] jeśli za wolno: sprawdź mniejszą kwantyzację

## [TTS-SETUP] ElevenLabs + Piper: konto, głos, smoke test
labels: owner:P4, area:ai, type:spike, prio:P0
milestone: M0 Fundament
depends:

- [ ] konto ElevenLabs, wybór **polskiego** głosu przewodnika, zapisz `voice_id` (nie klucz!) w komentarzu
- [ ] smoke test REST text-to-speech (model wielojęzyczny) → MP3 z polskim zdaniem; sprawdź limit znaków na planie
- [ ] Piper (offline fallback): `pl_PL-gosia-medium` (albo `darkman` / `mc_speech`), WAV → MP3 przez ffmpeg
- [ ] klucz **wyłącznie** w `server/.env` (ignorowany przez git)

## [UI-SKETCH] Szkic UX ekranów (15 min z zespołem)
labels: owner:P5, area:app, type:docs, prio:P1
milestone: M0 Fundament
depends:

Szkic (papier/Figma) i zdjęcie w komentarzu: **Start** (wyjaśnienie prywatności + `LocationButton`), **Spacer** (pasek trasy z kolejnymi zabytkami i ETA, radar, teleprompter, odtwarzacz, etykieta AI/szablon/głos, stan sesji), **Deep dive**, **Prywatność na żywo**, **Ustawienia**. Uzgodnij z P2, jakie pola stanu potrzebujesz z `WalkViewModel`.

## [MODELS-GEO] Modele danych + geo.ets
labels: owner:P2, area:app, type:feature, prio:P0
milestone: M1 Draft E2E
depends: SCAFFOLD

- [ ] `model/`: `GeoFix`, `Poi`, `Segment`, `Claim`, `SegmentKind`, `Interest` 1:1 z `docs/CONTRACTS.md`
- [ ] parser `rawfile/pois-krakow.json` i `demo-route-krakow.json`
- [ ] `guide/geo.ets`: haversine, azymut, `along`/`cross` względem kursu, normalizacja kątów
- [ ] testy Hypium: znane odległości (np. Barbakan ↔ Sukiennice ≈ 480 m), lewo/prawo, przejście przez 0°/360°

## [LOCATION] LocationProvider: Live + RouteReplay (debug)
labels: owner:P1, area:app, type:feature, prio:P0
milestone: M1 Draft E2E
depends: SPIKE-LOC, MODELS-GEO

- [ ] interfejs `LocationProvider { start(onFix, onError), stop() }`, emituje `GeoFix`
- [ ] `LiveLocationProvider`: `geoLocationManager` po kliknięciu `LocationButton`, mapowanie błędów (brak autoryzacji → `DENIED`)
- [ ] `RouteReplayProvider`: odtwarza `demo-route-krakow.json` w czasie rzeczywistym (opcjonalnie ×2/×4). **Tylko w buildzie debug**, w UI zawsze widoczny znacznik „SYMULACJA TRASY”
- [ ] przełącznik w ustawieniach debug

## [SESSION] WalkSession + cykl życia aplikacji
labels: owner:P1, area:app, type:feature, prio:P0
milestone: M1 Draft E2E
depends: LOCATION

- [ ] maszyna stanów z `docs/ARCHITECTURE.md` §5: `IDLE/ACQUIRING/WALKING/PAUSED/ERROR(NO_FIX|DENIED)`
- [ ] `onBackground` / wygaszenie ekranu → `PAUSED`: stop lokalizacji i stop odtwarzania
- [ ] timeout pierwszego fixa 15 s → `ERROR(NO_FIX)`
- [ ] testy Hypium wszystkich przejść (czas wstrzykiwany)

## [POIS-API] GET /v1/pois: Wikipedia GeoSearch, filtr, cache
labels: owner:P3, area:server, type:feature, prio:P0
milestone: M1 Draft E2E
depends: SERVER-SKEL

- [ ] klient MediaWiki GeoSearch (pl.wikipedia.org): `generator=geosearch` + `coordinates|pageprops|extracts|pageimages|info` (wzór działającego zapytania: `tools/gen_fixtures.py`). **Nie Wikidata SPARQL** (limit 1/min podczas awarii)
- [ ] filtr obszarów: odrzuć `type` ∈ {city, adm1st, adm2nd, adm3rd, country, region} i `dim ≥ 5000`; odrzuć brak `extract`
- [ ] normalizacja do `Poi`, `distanceM`, sortowanie, limit 50, walidacja parametrów (400)
- [ ] cache po komórce siatki ~100 m, TTL 24 h; awaria upstreamu → cache → `fixtures` (`source` w odpowiedzi)
- [ ] User-Agent zgodny z polityką Wikimedia
- [ ] testy bez sieci: nagrane odpowiedzi w `server/test/fixtures/`, test kontraktu

## [POI-REPO] PoiRepository w aplikacji (HTTP + fallback rawfile)
labels: owner:P3, area:app, type:feature, prio:P1
milestone: M1 Draft E2E
depends: SCAFFOLD, MODELS-GEO

- [ ] `PoiRepository.near(fix, radiusM): Promise<Poi[]>` przez `@kit.NetworkKit` http, timeout z `ApiConfig`
- [ ] błąd / timeout / pusty `API_BASE_URL` → POI z `rawfile/pois-krakow.json` filtrowane po odległości
- [ ] ponowne pobranie po przejściu > 150 m od ostatniego zapytania

## [MOTION-ITIN] MotionTracker + Itinerary
labels: owner:P2, area:app, type:feature, prio:P0
milestone: M1 Draft E2E
depends: MODELS-GEO

Algorytmy: `docs/ARCHITECTURE.md` §2.1–2.2.
- [ ] `MotionTracker`: odrzucanie złych fixów, EMA prędkości, kurs z przemieszczenia ≥ 15 m, `MOVING/STOPPED` z histerezą
- [ ] `Itinerary`: `upcoming` (along/cross, ETA, lewo/prawo), `passed`, `missed`, stabilność „następnego”
- [ ] testy na `demo-route-krakow.json`: kolejność POI zgodna z trasą; szum GPS nie zmienia `upcoming`

## [PLANNER] Templates + NarrationPlanner + GuideDirector
labels: owner:P2, area:app, type:feature, prio:P0
milestone: M1 Draft E2E
depends: MOTION-ITIN

Zasady: `docs/ARCHITECTURE.md` §2.3, szablony: `docs/CONTRACTS.md`.
- [ ] `Templates` dla wszystkich `SegmentKind` (te same co na serwerze)
- [ ] `NarrationPlanner`: priorytety, budżety słów z ETA, brak przerywania, przeterminowanie, „Tuż obok”, `DEEP_DIVE_OFFER` po zatrzymaniu
- [ ] `GuideDirector.step(state, input, tNow) → (state, actions[])` (akcje: `REQUEST_SEGMENT`, `PLAY_SEGMENT`, `OFFER_DEEP_DIVE`)
- [ ] na M1 wystarczy, że segmenty pochodzą z `Templates`; AI podłącza {{SEGMENT-SERVICE}}
- [ ] **10 scenariuszy z `docs/TESTING.md`** jako testy Hypium

## [VIEWMODEL] WalkViewModel + draft E2E (cel M1)
labels: owner:P2, area:app, type:feature, prio:P0
milestone: M1 Draft E2E
depends: SESSION, PLANNER, POI-REPO

- [ ] `WalkViewModel` (@ObservedV2): sesja, `upcoming` z ETA, aktualny segment, kolejka, oferta deep dive, źródło danych (live/fixture), znacznik symulacji
- [ ] spięcie: `LocationProvider → GuideDirector → (Templates) → stan`
- [ ] **Demo M1:** klik `LocationButton` → pozycja → POI → `ARRIVAL` z szablonu widoczny na ekranie (UI może być surowy)

## [UI-WALK] StartPage + WalkPage
labels: owner:P5, area:app, type:feature, prio:P0
milestone: M1 Draft E2E
depends: UI-SKETCH, SCAFFOLD

- [ ] `StartPage`: 2–3 zdania o prywatności, `LocationButton`, link do Prywatności
- [ ] `WalkPage`: `RouteStrip` (linia z kolejnymi zabytkami, ETA, lewo/prawo), `Radar` (Canvas: ty w środku, POI wg azymutu), `Teleprompter` (tekst bieżącego segmentu), `SessionBadge`, etykieta źródła tekstu i głosu
- [ ] na start na stanie mock, potem podpięte do `WalkViewModel` ({{VIEWMODEL}})
- [ ] stan `PAUSED`: przycisk „Kontynuuj spacer” (ponownie `LocationButton`)

## [SEGMENT-API] POST /v1/segment: Bielik + walidator ugruntowania
labels: owner:P4, area:server, area:ai, type:feature, prio:P0
milestone: M2 Feature complete
depends: LLM-SETUP, POIS-API

- [ ] prompty po polsku dla `WELCOME/ARRIVAL/BRIDGE/DEEP_DIVE` (styl: przewodnik w drodze, krótkie zdania, budżet `maxWords`); `BRIDGE` łączy dwa miejsca wspólnym wątkiem z obu źródeł
- [ ] `APPROACH/MISSED`: tylko szablony (szybkie, deterministyczne)
- [ ] Ollama `/api/chat`, `format` = JSON Schema `{title?, text, claims[{text, quote}]}`, `keep_alive`, `num_predict` z budżetu, timeouty z `CONTRACTS.md`
- [ ] **walidator:** każdy `quote` musi występować w tekście źródłowym (po normalizacji białych znaków/cudzysłowów); liczby/lata z `text` muszą występować w źródle; inaczej retry ×1, potem szablon + `warnings`
- [ ] serwer bierze źródło z cache POI, **nie od klienta**
- [ ] cache po kluczu (typ, poiId, fromPoiId, interests, maxWords, wersja promptu)
- [ ] testy z mockiem Ollamy: poprawny JSON, nie-JSON, timeout, halucynowany rok, zmyślony cytat

## [TTS-API] TtsProvider + /v1/audio + warm
labels: owner:P4, area:server, area:ai, type:feature, prio:P0
milestone: M2 Feature complete
depends: TTS-SETUP, SEGMENT-API

- [ ] `TtsProvider`: `ElevenLabsTts` (MP3), `PiperTts` (WAV→MP3 ffmpeg), `NoTts`; łańcuch fallbacku wg `TTS_PROVIDER`
- [ ] `durationMs` z rzeczywistego pliku (np. z nagłówków MP3 / ffprobe)
- [ ] `GET /v1/audio/:id.mp3` z cache; pliki audio poza gitem
- [ ] `npm run warm`: przechodzi trasę demo i generuje tekst + audio dla ARRIVAL/BRIDGE/WELCOME wszystkich POI na trasie (oszczędza limit ElevenLabs i czas Bielika)
- [ ] testy z mockami: błąd ElevenLabs → Piper; oba → `audioUrl: null`

## [SEGMENT-SERVICE] SegmentService w aplikacji: prefetch z deadline
labels: owner:P3, area:app, area:ai, type:feature, prio:P0
milestone: M2 Feature complete
depends: SEGMENT-API, PLANNER

- [ ] `SegmentService.request(req, deadlineMs): Promise<Segment>`; po deadline zwraca lokalny szablon (i ignoruje spóźnioną odpowiedź albo podmienia ją, jeśli segment jeszcze nie grał)
- [ ] obsługa akcji `REQUEST_SEGMENT` z `GuideDirector` (prefetch ARRIVAL(next) i BRIDGE(current→next))
- [ ] limit równoległych zapytań (1–2), bo Bielik na CPU jest wąskim gardłem
- [ ] testy: odpowiedź przed deadline / po deadline / błąd sieci

## [PLAYER] NarratorPlayer (AVPlayer) + synchronizacja teleprompteru
labels: owner:P5, area:app, type:feature, prio:P0
milestone: M2 Feature complete
depends: SPIKE-AUDIO, UI-WALK

- [ ] `NarratorPlayer.play(segment)`: AVPlayer z `audioUrl`; koniec odtwarzania → informacja do `GuideDirector` (narrator wolny)
- [ ] brak audio → „czytanie” tekstu w tempie ~2,5 słowa/s (ten sam mechanizm czasu)
- [ ] teleprompter odsłania tekst zsynchronizowany z postępem audio (proporcjonalnie do długości zdań)
- [ ] stop przy `PAUSED`, pauza / wznów, przełącznik „głos wył.”

## [DEEP-SOURCE] Pełniejszy tekst źródła dla deep dive
labels: owner:P3, area:server, type:feature, prio:P1
milestone: M2 Feature complete
depends: POIS-API

- [ ] pobranie pełniejszego tekstu artykułu (MediaWiki extracts bez `exintro`, przycięte do ~6–8 tys. znaków, sekcje po nagłówkach)
- [ ] cache; używane przez `DEEP_DIVE` w {{SEGMENT-API}}
- [ ] test bez sieci

## [DEEP-UI] Deep dive: oferta przy zatrzymaniu + arkusz
labels: owner:P5, area:app, type:feature, prio:P1
milestone: M2 Feature complete
depends: PLAYER, VIEWMODEL

- [ ] `DEEP_DIVE_OFFER` → nienachalny przycisk „Opowiedz więcej o {name}”
- [ ] po akceptacji: `DeepDiveSheet` z dłuższą narracją (audio + tekst), zdjęcie, link do źródła, etykieta AI
- [ ] ruszenie z miejsca → arkusz się zwija, przewodnik wraca do trasy

## [PRIVACY-SETTINGS] Ekran Prywatność na żywo + Ustawienia
labels: owner:P5, area:app, type:feature, prio:P1
milestone: M2 Feature complete
depends: VIEWMODEL

- [ ] Prywatność: stan autoryzacji (aktywna / wygasła), liczba odczytów lokalizacji w sesji, „co wysyłamy” (tylko id miejsc + zainteresowania), „stałe uprawnienia: 0”
- [ ] Ustawienia: zainteresowania (`Interest[]`), głos wł./wył., (debug) symulacja trasy

## [AI-EVAL] Ewaluacja AI + sekcja „AI feature disclosure”
labels: owner:P4, area:ai, type:test, prio:P1
milestone: M2 Feature complete
depends: SEGMENT-API, TTS-API

- [ ] `server/eval/`: 10 POI z trasy × (ARRIVAL, BRIDGE, DEEP_DIVE): % przechodzących walidację za 1. razem, średni czas generacji, ręczna ocena 1–5 (poprawność, płynność, „przewodnikowość”)
- [ ] wyniki w `AI_WORKFLOW.md` → „AI feature disclosure”: model, przepływ, dane i prywatność (co idzie do ElevenLabs), ograniczenia, fallbacki

## [E2E-QA] E2E checklista + audyt uprawnień i sekretów
labels: owner:P1, area:app, type:test, prio:P0
milestone: M2 Feature complete
depends: VIEWMODEL, SEGMENT-SERVICE, PLAYER

- [ ] cała checklista z `docs/TESTING.md` na emulatorze; wyniki (✅/❌ + uwagi) w komentarzu
- [ ] `hdc shell bm dump -n <bundle>`: brak uprawnień lokalizacji
- [ ] `git log -p | grep -i -E "xi-api-key|elevenlabs_api_key|sk_"`: pusto; brak `.env`, `.p12`, audio w repo
- [ ] logi release bez współrzędnych

## [README] README: setup, build, run
labels: owner:P3, area:docs, type:docs, prio:P0
milestone: M3 Zgłoszenie
depends: SPIKE-NET, LLM-SETUP

Obca osoba ma uruchomić projekt z samego README:
- [ ] wymagania i wersje (DevEco, SDK API 20/23/24, Node 22, Ollama, model, ffmpeg/Piper opcjonalnie)
- [ ] aplikacja: build, instalacja `.hap`, emulator (region CN, tworzenie urządzenia), ustawianie GPS / trasy
- [ ] serwer: `.env` z `.env.example`, Ollama + Bielik, ElevenLabs (opcjonalnie), `npm run warm`, firewall
- [ ] tryb offline bez serwera (co działa, a co nie)
- [ ] co jest symulowane (trasa w debug) i jak to rozpoznać

## [DEMO] Scenariusz i nagranie demo
labels: owner:P5, area:docs, type:docs, prio:P0
milestone: M3 Zgłoszenie
depends: E2E-QA

- [ ] scenariusz ≤ 2:30: problem → `LocationButton` (zero uprawnień) → spacer z płynnymi przejściami → zatrzymanie i deep dive → wyjście w tło = utrata lokalizacji → tryb offline
- [ ] nagranie **przed** ostatnią godziną; plik + link w README
- [ ] jasno pokazane, co jest symulowane (GPS emulatora)

## [RELEASE] Podpisany .hap + GitHub Release
labels: owner:P1, area:app, type:feature, prio:P0
milestone: M3 Zgłoszenie
depends: E2E-QA

- [ ] podpis w DevEco (File → Project Structure → Signing Configs); **keystore i hasła poza repo**
- [ ] build release `.hap`, instalacja na czystym emulatorze
- [ ] GitHub Release z `.hap`, sumą SHA-256 i krótkim changelogiem

## [AIWF-FINAL] Finalizacja AI_WORKFLOW.md i ARCHITECTURE.md
labels: owner:P5, area:docs, type:docs, prio:P0
milestone: M3 Zgłoszenie
depends: AI-EVAL

- [ ] zebrane wpisy z PR-ów, sekcje: narzędzia, prompty, workflow, nieudane podejścia, ograniczenia, lekcje
- [ ] `docs/ARCHITECTURE.md` zgodne z tym, co faktycznie zbudowaliśmy (usunąć to, czego nie zrobiliśmy)

## [CARD] (stretch) Karta usługi „Teraz w pobliżu”
labels: owner:P2, area:app, type:feature, prio:P2
milestone: M2 Feature complete
depends: VIEWMODEL

Karta (Form Kit) z najbliższym zabytkiem i ostatnią historią; klik otwiera aplikację. Tylko gdy wszystkie P0/P1 są gotowe.

## [PERSONA] (stretch) Styl przewodnika
labels: owner:P4, area:ai, type:feature, prio:P2
milestone: M2 Feature complete
depends: SEGMENT-API

Wybór stylu w ustawieniach: „klasyczny”, „legendy”, „dla dzieci”. Wpływa tylko na prompt, ugruntowanie bez zmian.
