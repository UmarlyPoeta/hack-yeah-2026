# Kontrakty danych i API

**Jedyne źródło prawdy** dla danych między aplikacją a serwerem. Zmiana kontraktu = PR, który zmienia ten plik i oba końce (albo PR-y połączone w opisie). Przykładowe dane: `fixtures/pois-krakow.json`, `fixtures/demo-route-krakow.json`.

## Typy

```ts
interface GeoFix {            // jeden odczyt lokalizacji
  lat: number; lon: number;   // WGS84
  accuracyM: number;
  t: number;                  // ms, zegar monotoniczny
}

interface Poi {
  id: string;                 // "plwiki:<pageid>", stabilne
  name: string;               // "Sukiennice w Krakowie"
  summary: string;            // wstęp artykułu (plain text): źródło faktów dla AI i szablonów
  lat: number; lon: number;
  kind: string | null;        // "building" | "landmark" | null
  wikidataId: string | null;  // "Q1072350"
  imageUrl: string | null;
  sourceUrl: string;          // link do artykułu (licencja CC BY-SA 4.0), pokazywany w UI
  importance: number;         // 0..1: log(1 + liczba wersji językowych) / log(41), obcięte do 1 (#40)
  role: "sight" | "area";     // area = ulica, plac, dzielnica: nigdy ARRIVAL, tylko tło (#40)
  partOfId: string | null;    // id POI, którego ten jest częścią (Wikidata P361), np. galeria → Sukiennice (#40)
  distanceM?: number;         // tylko w odpowiedzi /v1/pois
}
// Aplikacja przyjmuje dane bez importance/role/partOfId (starsze fixtures):
// importance = min(1, długość summary / 2000), role = "sight", partOfId = null.

type SegmentKind = "WELCOME" | "APPROACH" | "ARRIVAL" | "BRIDGE" | "DEEP_DIVE" | "MISSED";
type Interest = "architektura" | "historia" | "sztuka" | "ludzie" | "legendy";

interface Segment {
  id: string;                 // hash klucza cache; stabilny dla tych samych wejść
  kind: SegmentKind;
  poiId: string;              // POI, którego dotyczy (dla BRIDGE: docelowy)
  fromPoiId: string | null;   // tylko BRIDGE
  text: string;               // po polsku, gotowy do przeczytania
  claims: Claim[];            // [] dla szablonów
  origin: "ai" | "template";
  llmModel: string | null;    // np. "bielik-4.5b-v3.0-instruct:Q8_0"
  audioUrl: string | null;    // "/v1/audio/<id>.mp3" albo null (brak TTS)
  durationMs: number | null;  // prawdziwa długość audio
  voice: string | null;       // "elevenlabs:<voice>" | "piper:pl_PL-gosia-medium"
  sourceUrls: string[];
  warnings: string[];         // np. "validation_retry", "llm_unavailable", "tts_fallback_piper", "tts_unavailable"
}

interface Claim { text: string; quote: string; }  // quote = DOSŁOWNY fragment tekstu źródłowego
```

## API serwera (`/v1`)

Odpowiedzi to JSON w UTF-8 (poza `/v1/audio`). Błędy mają format `{ "error": { "code": string, "message": string } }`.

### `GET /v1/health`
`200 { "ok": true, "version": "0.1.0", "llm": { "ok": bool, "model": string }, "tts": { "ok": bool, "provider": "elevenlabs"|"piper"|"none" } }`

### `GET /v1/pois?lat=&lon=&radius=`
- `radius` 50–1000 m, domyślnie 300.
- `200 { "pois": Poi[], "source": "live"|"cache"|"fixture", "warnings": string[] }`, posortowane po `distanceM`, maks. 50.
- Serwer szuka w dwóch zasięgach wokół środka komórki ~150 m (#40): najbliższe miejsca (150 m, do 50) oraz ważne miejsca dalej (600 m, tylko `importance ≥ 0.6`), połączone bez duplikatów. Dzięki temu Wawel i katedra nie przegrywają z kamienicami. Parafie, diecezje i organizacje bez budynku są odrzucane (Wikidata P31). Reguły: `server/src/pois/poi-rules.json` (te same w `tools/gen_fixtures.py`).
- `warnings`: `"wikidata_unavailable"` (role z prefiksów nazw, `partOfId: null`), `"importance_fallback"` (importance z długości streszczenia, bez wyszukiwania dalekiego). Wynik z ostrzeżeniem nie jest zapamiętywany jako świeży.
- `400 invalid_params`. Gdy upstream nie działa: `200` z `source: "cache"|"fixture"`, nigdy 5xx, jeśli są jakiekolwiek dane.

### `POST /v1/segment`
```json
{ "kind": "ARRIVAL", "poiId": "plwiki:123", "fromPoiId": null,
  "interests": ["historia"], "maxWords": 90, "voice": true }
```
- Serwer sam bierze tekst źródłowy z cache POI. **Nie przyjmuje tekstu źródłowego od klienta** (ochrona przed prompt injection).
- `APPROACH` i `MISSED` są generowane z szablonu (krótkie, deterministyczne), a TTS jest opcjonalny.
- `200 Segment` także przy awarii LLM albo TTS, wtedy z `origin`/`warnings` odpowiednio.
- `404 unknown_poi`, `400 invalid_params`.
- Timeouty serwera: LLM 45 s (`DEEP_DIVE` 90 s), TTS 20 s. Klient ma deadline z plannera; po nim używa szablonu lokalnie.

### `GET /v1/audio/<segmentId>.mp3`
`200 audio/mpeg` z cache albo `404`.

### Łącze telefon ↔ zegarek: `/v1/link/<room>/messages` (#51)
Na emulatorach Super Device nie widzi urządzeń, więc oba łączą się przez serwer (`hdc rport tcp:8787 tcp:8787`, w aplikacji `http://127.0.0.1:8787`). `<room>` to kod parowania (`[A-Za-z0-9_-]{1,32}`, telefon pokazuje 4 cyfry).
- `POST` `{ "from": "phone"|"watch", "body": { ... } }` → `200 { "seq": number, "t": number }`. `body` to dowolny obiekt JSON ustalony w #50, maks. 4 KB całości (`413`).
- **Bez pozycji:** pola `lat`, `lon`, `lng`, `latitude`, `longitude`, `position`, `coords`, `coordinates`, `geoFix`, `accuracyM` na dowolnym poziomie → `400 position_not_allowed` (#56). Łącze niesie stan przewodnika, nie lokalizację.
- `GET ?after=<seq>` → `200 { "messages": [{ "seq", "t", "from", "body" }], "lastSeq": number }`, wiadomości z `seq > after`, rosnąco. Klient pyta co 500–1000 ms i zapamiętuje ostatni `seq`.
- Wiadomości są tylko w pamięci serwera: maks. 200 na pokój, TTL 10 min, maks. 100 pokojów (`503 too_many_rooms`). Nie trafiają do logu ani na dysk.

## Szablony (identyczne w aplikacji i na serwerze)

| Kind | Szablon |
|---|---|
| WELCOME | „Zaczynamy spacer. Pierwszy przystanek: {next.name}, ok. {m} m przed nami.” |
| APPROACH | „Za ok. {m} m po {lewej/prawej}: {name}.” / „Tuż obok: {name}.” |
| ARRIVAL | pierwsze 2–3 zdania `summary` (≤ budżet słów) |
| BRIDGE | „Idziemy dalej. Przed nami {next.name}.” |
| DEEP_DIVE | pierwsze ~6 zdań `summary` |
| MISSED | „Po {lewej/prawej} minęliśmy {name}.” |

## Konfiguracja aplikacji
`Projekt/entry/src/main/ets/data/ApiConfig.ets`: `API_BASE_URL` (np. `http://192.168.x.y:8787`; pusty = tryb offline), `REQUEST_TIMEOUT_MS = 20000` (`/v1/pois`), `SEGMENT_TIMEOUT_MS = 50000` i `DEEP_DIVE_TIMEOUT_MS = 95000` (`/v1/segment`: dłuższe niż timeouty LLM serwera, żeby spóźniona odpowiedź mogła jeszcze zastąpić szablon). Deadline z plannera jest krótszy: po nim `SegmentService` od razu oddaje lokalny szablon. `SegmentService` zamienia względny `audioUrl` na pełny adres (`API_BASE_URL + audioUrl`), gotowy dla AVPlayera. HTTP bez TLS działa w modelu Stage bez dodatkowej konfiguracji (FAQ Network Kit), wystarczy uprawnienie `INTERNET`.

## Konfiguracja serwera (`server/.env.example`)
`PORT`, `OLLAMA_URL`, `LLM_MODEL`, `TTS_PROVIDER` (`elevenlabs|piper|none`), `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID`, `ELEVENLABS_MODEL_ID`, `PIPER_BIN`, `PIPER_VOICE`, `FFMPEG_BIN`, `CACHE_DIR`.
