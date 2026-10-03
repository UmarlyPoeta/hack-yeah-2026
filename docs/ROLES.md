# Role: kto co robi, od czego zaczyna, kiedy jest „gotowe”

Każdy ma **pionowy kawałek**, który kończy się czymś widocznym i ma własne testy. Granice między ludźmi to interfejsy z [`CONTRACTS.md`](CONTRACTS.md). Dzięki temu możesz pracować na danych z `fixtures/`, zanim reszta skończy swoje części.

Kto ma Windows albo Maca z procesorem M, instaluje DevEco Studio według [README challenge'u](https://github.com/onirodeveloper/hackyeah2026-challenge) (region CN, `INSTALLATION_PROMPT.md`). Kto ma Linuksa, zaczyna od pracy bez DevEco (serwer, logika na fixtures, projekt UI na papierze) i buduje przez stację P1 albo Oniro App Builder.

---

## P1: Platforma i integracja (lead)

**Po co ta rola:** bez działającego projektu, lokalizacji i sieci nikt nie zobaczy swojej pracy na emulatorze. P1 jest pierwszą osobą, która musi coś dowieźć, i ostatnią, która klika „merge”.

**Twoje pliki:** projekt DevEco (`AppScope/`, `entry/` szkielet, `build-profile.json5`, `module.json5`), `session/WalkSession.ets`, `location/*`, podpisywanie, GitHub Release.

**Pierwsze 90 minut (M0):**
1. Projekt z **Hackathon Template**: Phone, Compatible SDK 6.0.0 (API 20), compile 23, target 24. Push na `main`. **To odblokowuje wszystkich.**
2. **Spike lokalizacji:** pusta strona z `LocationButton` + `geoLocationManager`. Odpowiedz w issue na pytania:
   - czy trzeba deklarować uprawnienie w `module.json5`,
   - czy działa z GPS ustawionym w panelu emulatora,
   - czy emulator umie odtworzyć trasę (GPX albo kolejne punkty),
   - co dokładnie dzieje się po wyjściu do ekranu głównego.
3. **Spike sieci:** emulator robi `GET http://<IP-laptopa>:8787/v1/health`. Czy HTTP bez TLS przechodzi, czy trzeba coś skonfigurować.

**Potem:** `LiveLocationProvider` i `RouteReplayProvider` (debug, z wyraźnym znaczkiem „SYMULACJA” w UI), `WalkSession` z testami przejść, integracja kolejnych PR-ów, audyt uprawnień i sekretów, podpisany `.hap`, Release.

**Gotowe, gdy:** klik `LocationButton` na czystej instalacji daje strumień `GeoFix`, wyjście w tło daje `PAUSED`, a `bm dump` nie pokazuje uprawnień lokalizacji.

**Zależysz od:** nikogo. **Od ciebie zależą:** wszyscy (szkielet), P2 i P5 (strumień lokalizacji).

---

## P2: Silnik przewodnika

**Po co ta rola:** to „mózg” i główny argument w kryterium Intelligent. Aplikacja nie opowiada losowo, tylko jak przewodnik, który wie, dokąd idziesz.

**Twoje pliki:** `model/*`, `guide/*` (geo, MotionTracker, Itinerary, NarrationPlanner, Templates, GuideDirector), `viewmodel/WalkViewModel.ets`, testy Hypium.

**Jak zacząć bez emulatora:** cała logika to czyste funkcje. Wejście to `fixtures/demo-route-krakow.json` (180 punktów, 1,46 km, z czasem `t`) i `fixtures/pois-krakow.json` (77 prawdziwych miejsc). Wyjście to lista segmentów z czasami. Najpierw napisz test „cała trasa daje sensowną sekwencję”, potem implementuj. Algorytmy są opisane w [`ARCHITECTURE.md` §2](ARCHITECTURE.md).

**Kolejność:** modele + `geo` → `MotionTracker` → `Itinerary` → `Templates` → `NarrationPlanner` → `GuideDirector` → `WalkViewModel`.

**Gotowe, gdy:** replay trasy demo daje sekwencję WELCOME → APPROACH → ARRIVAL → BRIDGE → …, przechodzi 10 scenariuszy z [`TESTING.md`](TESTING.md), a `WalkViewModel` wystawia stan, który P5 może narysować.

**Zależysz od:** P1 (szkielet projektu), P3 (interfejs `SegmentService`, na start możesz go zamockować). **Od ciebie zależą:** P5 (stan do UI), P4 (kiedy i z jakim budżetem prosić o segment).

---

## P3: Dane i serwer bazowy

**Po co ta rola:** bez miejsc nie ma o czym opowiadać. Ty dbasz o to, żeby dane były prawdziwe, szybkie i dostępne nawet bez internetu.

**Twoje pliki:** `server/` (szkielet HTTP, config, `/v1/health`, `/v1/pois`, cache), `entry/.../data/PoiRepository.ets`, `entry/.../data/SegmentService.ets` (klient HTTP segmentów z prefetchem), `fixtures/`, `tools/gen_fixtures.py`, `README.md` (setup/build/run).

**Jak zacząć:** serwer w Node 22 działa na każdym systemie. Najpierw szkielet z `node:http` + `node --test`, potem `/v1/pois` na **MediaWiki GeoSearch API** pl.wikipedia.org. Gotowy działający przykład zapytania jest w `tools/gen_fixtures.py`. **Nie używaj Wikidata SPARQL**: w trakcie hackathonu ma limit 1 zapytania na minutę. Nagraj prawdziwe odpowiedzi do `server/test/fixtures/`, żeby testy nie potrzebowały sieci.

**Potem:** `PoiRepository` w aplikacji: HTTP z timeoutem, a przy błędzie dane z `rawfile` (kopia `fixtures/pois-krakow.json`). Pełniejszy tekst artykułu dla deep dive (wewnętrzny, używa go P4). `SegmentService`: klient `/v1/segment` z deadline z plannera (po deadline lokalny szablon), limit 1–2 równoległych zapytań. Na koniec README, żeby obca osoba uruchomiła aplikację i serwer.

**Gotowe, gdy:** `/v1/pois` przechodzi testy kontraktu, cache działa, a aplikacja pokazuje POI zarówno z serwerem, jak i bez niego.

**Zależysz od:** nikogo (serwer), P1 (szkielet aplikacji), P4 (`/v1/segment` dla `SegmentService`; do tego czasu mock). **Od ciebie zależą:** P4 (źródła tekstu), P2 i P5 (POI i segmenty w aplikacji), ocena „Reproducibility” (README).

---

## P4: AI i głos

**Po co ta rola:** to robi z aplikacji przewodnika. Bielik pisze, ElevenLabs mówi. Twoim zadaniem jest, żeby **nie zmyślał, mieścił się w czasie i zawsze coś powiedział**.

**Twoje pliki:** `server/src/{segment,llm,tts,validate}/`, `server/scripts/warm.js`, `server/eval/`, sekcja „AI feature disclosure” w `AI_WORKFLOW.md`.

**Jak zacząć (M0):**
1. Zainstaluj **Ollamę** i Bielika (`Bielik-4.5B-v3.0-Instruct`, GGUF z Hugging Face `speakleash`, kwantyzacja Q4). Zmierz czas generacji 100 słów po polsku na laptopie, który będzie serwerem. Od tego zależy strategia prefetchu.
2. Konto **ElevenLabs**: wybierz polski głos, zapisz `voice_id`, sprawdź limit znaków. Klucz trafia **tylko** do `server/.env`.

**Potem:**
- prompty per typ segmentu (ARRIVAL, BRIDGE, DEEP_DIVE, WELCOME),
- `format` = JSON Schema w Ollamie,
- walidator ugruntowania (cytaty i liczby muszą być w źródle) + retry + szablon,
- `TtsProvider` (ElevenLabs → Piper → brak),
- cache tekstu i audio, `/v1/audio`,
- `npm run warm` dla trasy demo,
- mini-ewaluacja (10 POI × 3 typy).

**Gotowe, gdy:** `POST /v1/segment` zwraca ugruntowany tekst z MP3, każda awaria (Ollama, ElevenLabs, timeout, zły JSON) kończy się sensownym fallbackiem z `warnings`, a ewaluacja jest opisana w `AI_WORKFLOW.md`.

**Zależysz od:** P3 (szkielet serwera, źródła POI). **Od ciebie zależą:** P2 (segmenty), P5 (audio).

---

## P5: UI/UX, odtwarzacz i demo

**Po co ta rola:** jury ocenia to, co widzi i słyszy przez 2 minuty demo. Ty decydujesz, czy „przewodnik idący z tobą” jest odczuwalny.

**Twoje pliki:** `pages/*`, `components/*` (RouteStrip, Radar, Teleprompter, DeepDiveSheet, SessionBadge), `audio/NarratorPlayer.ets`, scenariusz i nagranie demo, redakcja `AI_WORKFLOW.md`.

**Jak zacząć (M0):**
1. **Spike dźwięku:** czy emulator odtwarza MP3 przez AVPlayer na głośnikach laptopa. Wystarczy dowolny MP3 w `rawfile`.
2. Szkic ekranów na papierze albo w Figmie, uzgodniony z zespołem w 15 minut. Potem implementacja na danych mock (stan `WalkViewModel` możesz na start wpisać na sztywno).

**Ekrany:**
- **Start:** czym jest aplikacja, co robi z lokalizacją, duży `LocationButton`.
- **Spacer:** pasek trasy („linia” z kolejnymi zabytkami przed tobą i ETA), radar, teleprompter z aktualną narracją i odtwarzaczem, etykieta AI/szablon/głos, stan sesji.
- **Deep dive:** arkusz z dłuższą opowieścią i źródłem.
- **Prywatność na żywo:** stan autoryzacji, liczba odczytów lokalizacji w tej sesji, co wysyłamy do serwera (tylko id miejsc).
- **Ustawienia:** zainteresowania, głos włącz/wyłącz.

**Gotowe, gdy:** cały spacer da się przejść na emulatorze bez dotykania niczego poza `LocationButton` i „Opowiedz więcej”, a demo jest nagrane.

**Zależysz od:** P2 (stan), P4 (audio), P1 (lokalizacja). **Od ciebie zależy:** ocena „Quality of demonstration” i „Reproducibility”.
